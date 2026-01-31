import json 
import random

jury_folder = "../Results/MultiAgents/GPTLens/GPT-3.5/ranker_default/primevul_results"
results_predict = []

with open('primevul_test_paired.jsonl', 'r') as json_file:
    json_list = list(json_file)

total = 0

def check_vul_label(jury_folder, i, label):
    global total
    try:
        f = open(jury_folder+"/"+str(i)+".txt", "r", encoding="utf8")
        lines = f.read()
        f.close()
    except:
        f = open(jury_folder+"/"+str(i)+".txt", "r")
        lines = f.read()
        f.close()   
    
    if "</think>" in lines:
        lines = lines.split("</think>")[-1]
    lines_updated = lines
    # print(lines_updated)
    vul_predict = 0
    if "NO: No security vulnerability" in lines_updated and "YES: A security vulnerability detected" in lines_updated:
        print(i)
    elif "NO: No security vulnerability" in lines_updated:
        vul_predict = 0
    elif "YES: A security vulnerability detected" in lines_updated or "YES: A security vulnerability" in lines_updated:
        vul_predict = 1
    else:
        # print("NOT FOUND")
        # print(i)
        if "YES" in lines_updated and "NO" in lines_updated:
            total += 1
        elif "YES" in lines_updated:
            vul_predict = 1
        elif "NO" in lines_updated:
            vul_predict = 0
        else:
            
            total += 1
    return vul_predict


codes = {}
for json_str in json_list:
    result = json.loads(json_str)
    codes[result["idx"]] = result["target"]
results_predict = []
vulnerabilities = []
results = {}
total_error = 0
for i in codes:
    vul_predict = check_vul_label(jury_folder, i, codes[i])
    
    vulnerabilities.append(codes[i])
    results_predict.append(vul_predict)

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




results = {"pc":0, "pv":0, "pb": 0, "pr":0}
#check pair
pair_count = 0
code_total = 0
for commit in pairs:
   idx_i = 0
   while idx_i+1 < len(pairs[commit]["target"]):
      pair_count += 1
      code_total += 2
    #   print()
      pair_1_label = pairs[commit]["target"][idx_i]
      pair_2_label = pairs[commit]["target"][idx_i+1]
      pair_1_predict = check_vul_label(jury_folder,pairs[commit]["idx"][idx_i],pair_1_label)
      pair_2_predict = check_vul_label(jury_folder,pairs[commit]["idx"][idx_i+1],pair_2_label)
      if pair_1_label == pair_1_predict and pair_2_label == pair_2_predict:
         results["pc"]+=1
      elif pair_1_predict == 1 and pair_2_predict == 1:
         results["pv"]+=1
      elif pair_1_predict == 0 and pair_2_predict == 0:
         results["pb"]+=1
      elif pair_1_predict == 0 and pair_2_predict == 1:
         results["pr"] +=1
      idx_i += 2

divider = 0
for i in results:
   divider += results[i]
print(jury_folder)
print("Pair: "+str(pair_count))
print("Codes: "+str(code_total))
for i in results:
   print(i)
   print((results[i]/divider)*100)


