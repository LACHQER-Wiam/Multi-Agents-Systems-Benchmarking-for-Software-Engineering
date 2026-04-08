We tested ReAct Agent using the claude haiku Large Language Model as a Logic of the Agent

# The ReAct Methodology

Instead of a single prompt, we implemented a loop:

    Thought: The agent identifies an import (e.g., import utils).

    Action: The agent uses a Virtual Tool to verify if utils.py exists in the context.

    Observation: The system provides feedback to the agent.

    Final Act: The agent compiles the list only after verification.

# claude-3-haiku-20240307

| Language | Total Input Tokens	| Total Output Tokens | EMR |
| :--- | :--- | :--- | :--- |
| Python | 874,126 | 15,380 | 8.89% |
| Java | 748,283 | 12,448 |	0.56% |
| JavaScript | 18,617 | 12,600 | 8.33% |
| C | 936,701 | 18,617 | 8.33% |
| C++  | 936,701 | 20,621 |	10% |
| C# | 851,125 | 19,605 | 8.89% |
| PHP | 725,408 | 12,572 | 12.22% |
| TypeScript | 700,408 | 17,992 | 9.44% |


# claude-haiku-4-5
| Language | Total Input Tokens	| Total Output Tokens | EMR |
| :--- | :--- | :--- | :--- |
| Python | 2,017,793 | 110,912 | 76.67% |
| Java | 1,777,683 | 87,069 | 19.44% |
| JavaScript | 1,679,254 | 95,527 | 78.89% |
| C | 2,046,828 | 111,637 | 79.44% |
| C++  | 2,118,619 | 121,852 | 85.56% |
| C# | 1,884,751 | 115,733 | 56.11% |
| PHP | 1,692,465 | 95.663 | 56.67% |
| TypeScript | 1,586,351 | 94,019 | 80.56% |
