from __future__ import annotations

import re
from typing import TYPE_CHECKING, Any, List, Optional

from . import order_registry as OrderRegistry
from .base import BaseOrder
from agentverse.logging import logger

if TYPE_CHECKING:
    from agentverse.environments import BaseEnvironment


@OrderRegistry.register("judge")
class JudgeOrder(BaseOrder):
    """
    The order for a security researcher team.
    The agents speak in the following order:
      1. The security researcher speaks first
      2. Then the code author defends
      3. Then the judge summarizes
      4. After the above three finish, the jury makes the final decision
    """

    def get_next_agent_idx(self, environment: BaseEnvironment) -> List[int]:
        """
        There are 3 cycles * 3 roles = 9 messages. On the 10th message,
        the Jury speaks. No further turns after that.
        """
        print("**********************")

        turn_number = environment.cnt_turn  # how many messages so far
        print(turn_number)
        # We have 9 turns total (3 cycles * 3 roles) for SecurityResearcher → CodeAuthor → Judge.
        # Then on turn 9 (i.e., the 10th message), the Jury speaks.

        # if turn_number < 9:
            # For turns 0..8, we repeat S → C → J every 3 messages
            # step_in_cycle = 0 -> Security
            # step_in_cycle = 1 -> Code Author
            # step_in_cycle = 2 -> Judge
        if len(environment.last_messages) == 0:
        # If the game just begins or , we let only the police speak
            return [0]
        elif len(environment.last_messages) == 1:
            message = environment.last_messages[0]
            sender = message.sender
            if sender.startswith("security_researcher"):
                return [1]
            elif sender.startswith("code_author"):
                return [2]
            else:
                if turn_number < (environment.max_turns - 1):
                    return [0]
                else:
                    return [3]
            # step_in_cycle = turn_number % 3
            # if step_in_cycle == 0:
            #     idx = find_agent_idx_by_role("security_researcher")
            #     return [0] #if idx is not None else [0]
            # elif step_in_cycle == 1:
            #     idx = find_agent_idx_by_role("code_author")
            #     return [1] #if idx is not None else [0]
            # else:  # step_in_cycle == 2
            #     idx = find_agent_idx_by_role("moderator")
            #     return [2] #if idx is not None else [0]

        # elif turn_number == 9:
        #     # The 10th message -> Jury
        #     idx = find_agent_idx_by_role("review_board")
        #     return [3] #if idx is not None else [0]

        # After turn_number >= 10, no one else speaks
        return [0]
    #     # `is_grouped_ended`: whether the group discussion just ended
    #     # `is_grouped`: whether it is currently in a group discussion
    #     if environment.rule_params.get("is_grouped_ended", False):
    #         return [0]
    #     if environment.rule_params.get("is_grouped", False):
    #         return self.get_next_agent_idx_grouped(environment)
    #     else:
    #         return self.get_next_agent_idx_ungrouped(environment)

    # def get_next_agent_idx_ungrouped(self, environment: BaseEnvironment) -> List[int]:
    #     if len(environment.last_messages) == 0:
    #         # If the class just begins or no one speaks in the last turn, we let only the professor speak
    #         return [0]
    #     elif len(environment.last_messages) == 1:
    #         message = environment.last_messages[0]
    #         sender = message.sender
    #         content = message.content
    #         if sender.startswith("Professor"):
    #             if content.startswith("[CallOn]"):
    #                 # 1. professor calls on someone, then the student should speak
    #                 result = re.search(r"\[CallOn\] Yes, ([sS]tudent )?(\w+)", content)
    #                 if result is not None:
    #                     name_to_id = {
    #                         agent.name[len("Student ") :]: i
    #                         for i, agent in enumerate(environment.agents)
    #                     }
    #                     return [name_to_id[result.group(2)]]
    #             else:
    #                 # 2. professor normally speaks, then anyone can act
    #                 return list(range(len(environment.agents)))
    #         elif sender.startswith("Student"):
    #             # 3. student ask question after being called on, or
    #             # 4. only one student raises hand, and the professor happens to listen
    #             # 5. the group discussion is just over, and there happens to be only a student speaking in the last turn
    #             return [0]
    #     else:
    #         # If len(last_messages) > 1, then
    #         # 1. there must be at least one student raises hand or speaks.
    #         # 2. the group discussion is just over.
    #         return [0]
    #     assert (
    #         False
    #     ), f"Should not reach here, last_messages: {environment.last_messages}"

    # def get_next_agent_idx_grouped(self, environment: BaseEnvironment) -> List[int]:
    #     # Get the grouping information
    #     # groups: A list of list of agent ids, the i-th list contains
    #     #   the agent ids in the i-th group
    #     # group_speaker_mapping: A mapping from group id to the id of
    #     #   the speaker in the group
    #     # `groups` should be set in the corresponding `visibility`,
    #     # and `group_speaker_mapping` should be maintained here.
    #     if "groups" not in environment.rule_params:
    #         logger.warn(
    #             "The environment is grouped, but the grouping information is not provided."
    #         )
    #     groups = environment.rule_params.get(
    #         "groups", [list(range(len(environment.agents)))]
    #     )
    #     group_speaker_mapping = environment.rule_params.get(
    #         "group_speaker_mapping", {i: 0 for i in range(len(groups))}
    #     )

    #     # For grouped environment, we let the students speak in turn within each group
    #     next_agent_idx = []
    #     for group_id in range(len(groups)):
    #         speaker_index = group_speaker_mapping[group_id]
    #         speaker = groups[group_id][speaker_index]
    #         next_agent_idx.append(speaker)

    #     # Maintain the `group_speaker_mapping`
    #     for k, v in group_speaker_mapping.items():
    #         group_speaker_mapping[k] = (v + 1) % len(groups[k])
    #     environment.rule_params["group_speaker_mapping"] = group_speaker_mapping

    #     return next_agent_idx
