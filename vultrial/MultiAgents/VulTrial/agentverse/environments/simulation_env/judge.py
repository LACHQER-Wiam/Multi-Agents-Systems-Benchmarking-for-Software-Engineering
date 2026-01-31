import asyncio
from pathlib import Path
# import logging
from agentverse.logging import get_logger
from typing import Any, Dict, List

# from agentverse.agents.agent import Agent
from agentverse.agents.simulation_agent.conversation import BaseAgent

# from agentverse.environments.simulation_env.rules.base import Rule
from agentverse.environments.simulation_env.rules.base import SimulationRule as Rule
from agentverse.message import Message

logger = get_logger()

from .. import env_registry as EnvironmentRegistry
from ..base import BaseEnvironment


@EnvironmentRegistry.register("judge")
class JudgeEnvironment(BaseEnvironment):
    """
    A basic environment implementing the logic of conversation.

    Args:
        agents: List of agents
        rule: Rule for the environment
        max_turns: Maximum number of turns
        cnt_turn: Current turn number
        last_messages: Messages from last turn
        rule_params: Variables set by the rule
    """

    agents: List[BaseAgent]
    rule: Rule
    max_turns: int = 10
    cnt_turn: int = 0
    last_messages: List[Message] = []
    rule_params: Dict = {}
    id_save: str

    def __init__(self, rule, **kwargs):
        rule_config = rule
        order_config = rule_config.get("order", {"type": "sequential"})
        visibility_config = rule_config.get("visibility", {"type": "all"})
        selector_config = rule_config.get("selector", {"type": "basic"})
        updater_config = rule_config.get("updater", {"type": "basic"})
        describer_config = rule_config.get("describer", {"type": "basic"})
        # self.id_save = rule_config.get("id_save")
        rule = Rule(
            order_config,
            visibility_config,
            selector_config,
            updater_config,
            describer_config,
        )
        super().__init__(rule=rule, **kwargs)

    async def step(self) -> List[Message]:
        """Run one step of the environment"""

        # Get the next agent index
        agent_ids = self.rule.get_next_agent_idx(self)

        # Generate current environment description
        env_descriptions = self.rule.get_env_description(self)

        # Generate the next message
        messages = await asyncio.gather(
            *[self.agents[i].astep(env_descriptions[i], self.id_save, self.cnt_turn) for i in agent_ids]
        )

        # Some rules will select certain messages from all the messages
        selected_messages = self.rule.select_message(self, messages)
        self.last_messages = selected_messages
        self.print_messages(selected_messages)


        # Update the memory of the agents
        self.rule.update_memory(self)

        # Update the set of visible agents for each agent
        self.rule.update_visible_agents(self)

        self.cnt_turn += 1

        return selected_messages

    def print_messages(self, messages: List[Message]) -> None:
        for message in messages:
            if message is not None:
                # logging.info(f"{message.sender}: {message.content}")
                logger.info(f"{message.sender}: {message.content}")
                Path("results/all_record/").mkdir(parents=True, exist_ok=True)
                f = open("results/all_record/"+str(self.id_save)+".txt", "a")
                f.write(f"{message.sender}: {message.content}")
                f.write("\n")
                f.close()
                Path("results/output/"+str(self.id_save)).mkdir(parents=True, exist_ok=True)
                f = open("results/output/"+str(self.id_save)+"/"+str(self.cnt_turn)+".txt", "w")
                f.write(message.content)
                f.write("\n")
                f.close()

    def reset(self) -> None:
        """Reset the environment"""
        self.cnt_turn = 0
        self.rule.reset()
        for agent in self.agents:
            agent.reset()

    def is_done(self) -> bool:
        """Check if the environment is done"""
        if self.cnt_turn >= self.max_turns:
            Path("results/final_record/").mkdir(parents=True, exist_ok=True)
            f = open("results/final_record/"+str(self.id_save)+".txt", "w")
            f.write(self.last_messages[-1].content)
            f.close()
        return self.cnt_turn >= self.max_turns
