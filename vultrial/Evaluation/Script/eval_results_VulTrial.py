import json 
from pathlib import Path
jury_folders = []

# jury_folders.append("../Results/MultiAgents/VulTrial/GPT-3.5/final_record")
jury_folders.append("../Results/MultiAgents/VulTrial/GPT-4o/final_record")

results_predict = []
    
for jury_folder in jury_folders:
    print(jury_folder)
    with open('primevul_test_paired.jsonl', 'r') as json_file:
        json_list = list(json_file)

    codes = {}
    for json_str in json_list:
        result = json.loads(json_str)
        codes[result["idx"]] = result["target"]
    results_predict = []
    vulnerabilities = []
    results = {}
    total_error = 0
    
    #making pair

    pairs = {}
    number = 0
    test_idx = set()
    for json_str in json_list:
        result = json.loads(json_str)
        number += 1
        test_idx.add(result["idx"])
        if result["commit_id"] in pairs:
            pairs[result["commit_id"]]["target"].append(result["target"])
            pairs[result["commit_id"]]["idx"].append(result["idx"])
        else:
            pairs[result["commit_id"]] = {"target": [result["target"]], "idx": [result["idx"]] }
        #    pairs[result["commit_id"]]["idx"] = [result["idx"]]

    # print(len(pairs))
    total_in_pair = 0
    for commit in pairs:
        total_in_pair += len(pairs[commit]["target"])
        # if len(pairs[commit]["target"]) > 2:
        #     print("MOREEEE")
        #     print(commit) 
        #     print(len(pairs[commit]["target"]))
        #     print(pairs[commit]["target"])
        # elif len(pairs[commit]["target"]) == 1:
        #     print("****************************")
        #     print(commit)
        #     print(pairs[commit]["idx"])
    
    def check_condition(k, status):
        if status == "only_valid_high":
            if k["decision"] == "valid":
                if k["severity"] == "high":
                    return 1
        elif status == "action_and_valid_high":
            if k["recommended_action"] == "fix immediately":
                if k["decision"] == "valid":
                    if k["severity"] == "high":
                        return 1
        return None
    def check_vul_label(i, status):
        try:
            f = open(jury_folder+"/"+str(i)+".txt", "r", encoding="utf8")
            lines = f.read()
        except:
            f = open(jury_folder+"/"+str(i)+".txt", "r")
            lines = f.read()
        if "</think>" in lines:
            lines = lines.split("</think>")[-1]
            lines = lines.split('```json\n')[-1]
            lines = "```json\n" + lines
        lines_updated = lines.replace('```json\n', '').replace('\n```', '')
        f.close()
        try:
            vul_predict = 0
            jury_results = json.loads(lines_updated)
            try:
                
                for k in jury_results:
                    if check_condition(k, status):
                        vul_predict = check_condition(k,status)
            except Exception as e:
                if "verdicts" in jury_results:    
                    vul_predict = 0
                    for k in jury_results["verdicts"]:
                        if check_condition(k,status):
                            vul_predict = check_condition(k,status)
        except Exception as e:
            if "mitigate" in lines_updated.split("\n")[-1]:
                vul_predict = 1        
        return vul_predict

    for staty in ["action_and_valid_high"]:
        #vul  non-vul
        results = {"pc":0, "pv":0, "pb": 0, "pr":0}
        pair_count = 0
        code_total = 0
        results_predict = []
        vulnerabilities = []
        for commit in pairs:
            idx_i = 0
            while idx_i+1 < len(pairs[commit]["target"]):
                if Path(jury_folder+"/"+str(pairs[commit]["idx"][idx_i])+".txt").exists() and Path(jury_folder+"/"+str(pairs[commit]["idx"][idx_i+1])+".txt").exists():                    
                    pair_count += 1
                    code_total += 2
                    pair_1_label = pairs[commit]["target"][idx_i]
                    pair_2_label = pairs[commit]["target"][idx_i+1]
                    pair_1_predict = check_vul_label(pairs[commit]["idx"][idx_i], staty)
                    pair_2_predict = check_vul_label(pairs[commit]["idx"][idx_i+1], staty)
                    
                    results_predict.append(pair_1_predict)
                    results_predict.append(pair_2_predict)
                    vulnerabilities.append(pair_1_label)
                    vulnerabilities.append(pair_2_label)
                    if pair_1_label == pair_1_predict and pair_2_label == pair_2_predict:
                        results["pc"]+=1
                    elif pair_1_predict == 1 and pair_2_predict == 1:
                        results["pv"]+=1
                    elif pair_1_predict == 0 and pair_2_predict == 0:
                        results["pb"]+=1
                    elif pair_1_predict == 0 and pair_2_predict == 1:
                        results["pr"] +=1
                idx_i += 2
        results_sum = {}
        divider = 0
        for i in results:
            divider += results[i]
        print(jury_folder)
        print("Pair: "+str(pair_count))
        print("Codes: "+str(code_total))
        for i in results:
            print(i)
            print((results[i]/divider)*100)
            results_sum[i] = (results[i]/divider)*100     