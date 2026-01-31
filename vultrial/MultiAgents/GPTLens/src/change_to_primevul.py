import json
import argparse
import os

def rank_by_score(json_list):
    return sorted(json_list, key=lambda x: x["final_score"], reverse=True)

def run(args):
    # output file
    ranker_dir = f"ranker_{args.strategy}"
    prime_vul = "primevul_results"
    for filename in os.listdir(os.path.join("logs", args.auditor_dir, args.critic_dir, ranker_dir)):
        if not filename.endswith("sol"):
            continue
        filepath = os.path.join("logs",  args.auditor_dir, args.critic_dir, ranker_dir, filename)
        with open(filepath, "r") as f:
            ranker_output_list = json.load(f)
        vulnerability = 0
        for i in range(len(ranker_output_list)):
            if "final_score" in ranker_output_list[i]:
                if ranker_output_list[i]["final_score"] >= 5:
                    vulnerability = 1
        
        # Rank based on scores
        filepath = os.path.join("logs", args.auditor_dir, args.critic_dir,  ranker_dir, prime_vul, filename.replace(".sol",".txt"))
        # dump the file
        os.makedirs(os.path.dirname(filepath), exist_ok=True)

        with open(filepath, 'w') as f:
            if vulnerability == 0:
                f.write("NO: No security vulnerability.")
            else:
                f.write("YES: A security vulnerability detected.")

    print("Ranking finished...")

def parse_args():
    args = argparse.ArgumentParser()
    args.add_argument('--dataset', type=str, choices=['CVE'], default="CVE")
    args.add_argument('--auditor_dir', type=str, default="auditor_gpt-4_0.7_top3_1") #The auditor output directory
    args.add_argument('--critic_dir', type=str, default="critic_gpt-4_0_1") #The critic output directory
    args.add_argument('--strategy', type=str, default="default", choices=["default", "customize"])

    args = args.parse_args()
    return args

if __name__ == '__main__':
    args = parse_args()
    print(args)
    run(args)
