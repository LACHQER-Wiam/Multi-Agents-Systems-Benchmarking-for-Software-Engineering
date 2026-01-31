import json

with open('primevul_test_paired.jsonl', 'r') as json_file:
        json_list = list(json_file)

codes = {}
for json_str in json_list:
    result = json.loads(json_str)
    f = open("PrimeVul/"+str(result["idx"])+".sol", "w")
    f.write(result["func"])
    f.close()

