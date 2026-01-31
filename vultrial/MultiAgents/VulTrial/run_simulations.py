import os
import shutil
import subprocess
import sys
from pathlib import Path

def main(folder_path):
    target_file = "agentverse/tasks/simulation/vultrial/"+conf+"/config.yaml"
    command = ["python", "agentverse_command/main_simulation_cli.py", "--task", "simulation/vultrial/"+conf+"/"]

    # Check if the folder exists
    if not os.path.isdir(folder_path):
        print(f"Error: Folder {folder_path} does not exist.")
        sys.exit(1)

    # Iterate over each file in the folder
    for filename in os.listdir(folder_path):
        file_path = os.path.join(folder_path, filename)
        if os.path.isfile(file_path):
            print(f"Processing file: {file_path}")

            # Copy the file to the specific target file name

            shutil.copy(file_path, target_file)
            Path("results/final_record/").mkdir(parents=True, exist_ok=True)
            if not os.path.isfile("results/final_record/"+filename.split("/")[-1].split("-")[0]+".txt"):
                # Run the specified Python command
                try:
                    subprocess.run(command, check=True)
                except subprocess.CalledProcessError as e:
                    print(f"Error: Command failed for file {file_path}. Error: {e}")
                    sys.exit(1)
            else:
                print("SKIP")
    
    print("All files processed successfully.")

if __name__ == "__main__":
    conf = "vultrial_base"
    if len(sys.argv) == 2:
        if sys.arv[1] in ["vultrial_base", "vultrial_gpt35", "vultrial_moderator_tuned"]:
            conf = str(sys.argv[1])
            folder_path = "agentverse/tasks/simulation/vultrial/"+conf+"/configs"
            main(folder_path)
        else:
            print("Choose the VulTrial setting:")
            print("1. vultrial_base")
            print("2. vultrial_gpt35")
            print("3. vultrial_moderator_tuned")
