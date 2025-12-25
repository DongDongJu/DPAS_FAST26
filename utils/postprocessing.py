import os
import subprocess
import sys

class Results:
    """A simple example class"""
    def __init__(self, name):
        self.name = name
        self.results = {}

    def dump_results(self):
        print(self.name)
        print(self.results)

def parse_fio(filepath):
    fio_result = dict.fromkeys(['IOPS', '50.00th', '90.00th', '95.00th', '99.00th', '99.99th'])
    output_stream = os.popen("grep " + "'IOPS'" + " " + filepath)
    output = output_stream.read().strip()
    data = output.split()
    fio_result['IOPS'] = ''.join(c for c in data[1] if (c.isdigit() or c =='.'))

    output_stream = os.popen("grep " + "'50.00th'" + " " + filepath)
    output = output_stream.read().strip()
    data = output.split(",")

    for d in data:
        if "50.00th" in d:
            tmp = d.split("=")
            fio_result['50.00th'] = ''.join(c for c in tmp[1] if (c.isdigit() or c =='.'))

    output_stream = os.popen("grep " + "'90.00th'" + " " + filepath)
    output = output_stream.read().strip()
    data = output.split(",")
    for d in data:
        if "90.00th" in d:
            tmp = d.split("=")
            fio_result['90.00th'] = ''.join(c for c in tmp[1] if (c.isdigit() or c =='.'))
    
    output_stream = os.popen("grep " + "'95.00th'" + " " + filepath)
    output = output_stream.read().strip()
    data = output.split(",")
    for d in data:
        if "95.00th" in d:
            tmp = d.split("=")
            fio_result['95.00th'] = ''.join(c for c in tmp[1] if (c.isdigit() or c =='.'))

    output_stream = os.popen("grep " + "'99.00th'" + " " + filepath)
    output = output_stream.read().strip()
    data = output.split(",")
    for d in data:
        if "99.00th" in d:
            tmp = d.split("=")
            fio_result['99.00th'] = ''.join(c for c in tmp[1] if (c.isdigit() or c =='.'))
    
    output_stream = os.popen("grep " + "'99.99th'" + " " + filepath)
    output = output_stream.read().strip()
    data = output.split(",")
    for d in data:
        if "99.99th" in d:
            tmp = d.split("=")
            fio_result['99.99th'] = ''.join(c for c in tmp[1] if (c.isdigit() or c =='.'))

    return fio_result
    
def parse_ycsb(filepath):
    # READ INSERT SCAN UPDATE
    ycsb_result = dict.fromkeys(['ops/sec'])
    output_stream = os.popen("grep " + "ops/sec " + filepath)
    output = output_stream.read().strip()
    data = output.split()
    if len(data) < 3:
        # YCSB may have aborted or produced an unexpected output format.
        # Keep parsing best-effort instead of crashing.
        ycsb_result['ops/sec'] = "NA"
        return ycsb_result
    ycsb_result['ops/sec'] = data[2]


    output_stream = os.popen("tail -n4 "+ filepath +"| head -n1")
    output = output_stream.read().strip()
    data = output.split("[")
    for k in data[1:]:
        raw = k.split(":")
        key = raw[0]
        ycsb_result[key] = raw[1][:-2]
    
    return ycsb_result

def parse_filebench(filepath):
    filebench_result = dict.fromkeys(['ops/s', 'mb/s', 'ms/op'])
    output_stream = os.popen("grep " + "'IO Summary'" + " " + filepath)
    output = output_stream.read().strip()
    data = output.split()
    filebench_result['ops/s'] = data[5]
    filebench_result['mb/s'] = ''.join(c for c in data[9] if (c.isdigit() or c =='.'))
    filebench_result['ms/op'] = ''.join(c for c in data[10] if (c.isdigit() or c =='.'))

    return filebench_result

def parse_dbbench_randomread(filepath, dbbench_result):
    dbbench_result = dict.fromkeys(['micros/op', 'ops/s', 'MB/s', 'P50', 'P95', 'P99', 'P100'])
    output_stream = os.popen("grep " + "'readrandom'" + " " + filepath)
    output = output_stream.read().strip()
    data = output.split()
    dbbench_result['micros/op'] = data[2]
    dbbench_result['ops/s'] = data[4]
    dbbench_result['MB/s'] = data[10]
    
    output_stream = os.popen("grep " + "'db.get.micros'" + " " + filepath)
    output = output_stream.read().strip()
    data = output.split()
    dbbench_result['P50'] = data[3]
    dbbench_result['P95'] = data[6]
    dbbench_result['P99'] = data[9]
    dbbench_result['P100'] = data[12]
    
    return dbbench_result

def parse_dbbench(filepath):
    dbbench_result = {}
    output_stream = os.popen("grep " + "'readrandom'" + " " + filepath)
    output = output_stream.read().strip()
    
    if output != "":
        dbbench_result = parse_dbbench_randomread(filepath, dbbench_result)
    
    return dbbench_result

def wirte_results(benchmark, output_file):
    f = open(output_file, "a")
    f.write(benchmark.name + "\n")
    for key in benchmark.results:
        output_str = "{0}: {1}\n".format(key, benchmark.results[key])
        f.write(output_str)
    f.close()

def parse_cpu(filename, outputfile):
    f = filename
    cpu_list = []
    with open(f, "r") as r:
        raw_data = r.readlines()[5:]
        for data in raw_data:
            cpu = data.split()[-1][:-1]
            try:
                cpu_list.append(float(cpu))
            except:
                pass
    avg_cpu = str(round(sum(cpu_list)/len(cpu_list),2))

    f = open(output_file, "a")
    f.write("cpu: " + avg_cpu + "\n")
    f.write("===============\n")
    f.close()

def parse_global_cpu(filename, outputfile):
    f = filename
    cpu_list = []
    cpu_usr = 0.0
    cpu_sys = 0.0 
    with open(f, "r") as r:
        raw_data = r.readlines()[-1:]
        for data in raw_data:
            cpu_list = data.split()[2:5]
            cpu_usr = float(cpu_list[0])
            cpu_sys = float(cpu_list[2])

    f = open(output_file, "a")
    f.write("usr: " + str(cpu_usr) + " sys: " + str(cpu_sys) + "\n")
    f.write("===============\n")
    f.close()

if __name__ == "__main__":
    output_dir = "results"
    output_file = "results.txt"
    cpu_filename = "cpu_single_workload.txt"
    cpu_global_filename = "cpu_global_workload.txt"

    fio = Results("fio")
    ycsb = Results("ycsb")
    filebench = Results("filebench")
    dbbench = Results("dbbench")

    for filename in os.listdir(output_dir):
        if filename == "db_bench_output.log":
            result = subprocess.run(['cat', output_dir + "/db_bench_output.log"], stdout=subprocess.PIPE).stdout.decode('utf-8')
            if result.strip()!="None":
                dbbench.results = parse_dbbench(output_dir + "/db_bench_output.log")
        elif filename == "fb_output.txt":
            result = subprocess.run(['cat', output_dir + "/fb_output.txt"], stdout=subprocess.PIPE).stdout.decode('utf-8')
            if result.strip()!="None":
                filebench.results = parse_filebench(output_dir + "/fb_output.txt")
        elif filename == "fio_output.txt":
            result = subprocess.run(['cat', output_dir + "/fio_output.txt"], stdout=subprocess.PIPE).stdout.decode('utf-8')
            if result.strip()!="None":
                fio.results = parse_fio(output_dir + "/fio_output.txt")
        elif filename == "ycsb_output.txt":
            result = subprocess.run(['cat', output_dir + "/ycsb_output.txt"], stdout=subprocess.PIPE).stdout.decode('utf-8')
            if result.strip()!="None":
                ycsb.results = parse_ycsb(output_dir + "/ycsb_output.txt")

    if fio.results!={}:  
        wirte_results(fio, output_file)  
    
    if dbbench.results!={}:
        wirte_results(dbbench, output_file) 
    
    if ycsb.results!={}:
        wirte_results(ycsb, output_file)
    
    if filebench.results!={}:
        wirte_results(filebench, output_file) 
    
    if os.path.isfile(cpu_filename):
        parse_cpu(cpu_filename, output_file)

    if os.path.isfile(cpu_global_filename):
        parse_global_cpu(cpu_global_filename, output_file)