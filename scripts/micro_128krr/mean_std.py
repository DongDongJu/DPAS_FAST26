import os
import sys 
import numpy as np

def containsNumber(value):
    if "PAS_S0.1" in value:
        return False
    for character in value:
        if character.isdigit():
            return True
    return False

def isAscend(prev, cur):
    if cur > prev:
        return True
    else:
        return False

def isDescend(prev, cur):
    if cur < prev:
        return True
    else:
        return False

def checkingNumber(value_list):
    ret = []
    for x in value_list:
        if x == "":
            continue
        t = ""
        for data in x:
            if containsNumber(data) or data == ".":
                pass
            else:
                data = data.replace(data,"")
            t+=data
        ret.append(float(t))
    return ret 

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("usage {sys.argv[0]} [# of datas] [data_path] [ascend[1]/descend[0]]")
    f = open(sys.argv[2])

    write_file_name = sys.argv[2].split("/")[2].split(".")[0]
    if not os.path.exists("./result_data"):
        os.system("mkdir result_data")
    fd = open(f"./result_data/{write_file_name}.txt", "w")

    raw_data_dics = [{} for x in range(int(sys.argv[1]))]
    cur_data_idx = 0 
    prv = -1
    for line in f.readlines():
        if(containsNumber(line)):
            raw = line.split()
            if int(sys.argv[3]) == 1:
                if(isAscend(prv,int(float(raw[0]))) or prv == -1):
                    pass
                else:
                    cur_data_idx +=1 
                    if cur_data_idx >= int(sys.argv[1]):
                        cur_data_idx = 0 
            else:
                if(isDescend(prv,int(float(raw[0]))) or prv == -1):
                    pass
                else:
                    cur_data_idx +=1 
                    if cur_data_idx >= int(sys.argv[1]):
                        cur_data_idx = 0                                 
            prv = int(float(raw[0]))
            if raw[0] in raw_data_dics[cur_data_idx]:
                raw_data_dics[cur_data_idx][raw[0]].append(raw[1:])
            else:
                raw_data_dics[cur_data_idx][raw[0]] = [raw[1:]]

    for data_idx in range(int(sys.argv[1])):
        for k,v in raw_data_dics[data_idx].items():
            t = []
            for data in v:
                data = checkingNumber(data)
                t.append(data)
            raw_data_dics[data_idx][k] = t 
        # get mean
        print(f"data idx = {data_idx}", file=fd)
        print("mean", file=fd)
        for k,v in raw_data_dics[data_idx].items():
            result_str = f"{k}\t"
            for k in np.transpose(v):
                result_str += str(np.round(np.mean(k),2))+"\t"
            print(result_str, file=fd)

        print("std", file=fd)
        for k,v in raw_data_dics[data_idx].items():
            result_str = f"{k}\t"
            for k in np.transpose(v):
                result_str += str(np.round(np.std(k),2))+"\t"
            print(result_str, file=fd)
        print(file=fd)
