import os
import sys

def _csv_env(name: str, default: str):
    val = os.environ.get(name, default).strip()
    return [x.strip() for x in val.split(",") if x.strip()]

DEVICE_LIST = _csv_env("DPAS_DEVICE_LIST", "nvme0n1,nvme1n1,nvme2n1")
BS_LIST = [int(x) for x in _csv_env("DPAS_BS_LIST", "8,16,32,64,128")]
RW_FLAGS = _csv_env("DPAS_RW_FLAGS", "RR")
IO_MODE = _csv_env("DPAS_IO_MODE", "INT,CP,HP,EHP,PAS,DPAS")
REPEATS = int(sys.argv[1])

try:
    LOG_BASE_DIR = os.getcwd() + f"/fio_data"
except:
    print("usage python3 parse.py [data_path]")
    sys.exit(1)

def log_header_print(f):
	print("Threads".ljust(17), end="", file=f)
	for i, mode in enumerate(IO_MODE):
		end = "" if i < len(IO_MODE) - 1 else "\n"
		print(f"{mode}".ljust(17), end=end, file=f)

def getCPU(dir, repeat):
	f = open(dir + f"/fio_report_{repeat}.log")
	data = f.read()
	f.close()

	data = data.split("cpu          :")[1].split("\n")[0]
	data = data.split(", ")[:2]
	data[0] = float(data[0].split("=")[1].split("%")[0])
	data[1] = float(data[1].split("=")[1].split("%")[0])

	return round(data[0] + data[1], 2)

def getIOPS(dir, repeat):
	f = open(dir + f"/fio_report_{repeat}.log")
	data = f.read()
	f.close()

	data = data.split("IOPS=")[1].split(",")[0]
	if data[-1] == "k":
		#data = round(int(float(data[:-1]) * 1000) / 1000, 1)
		data = round(int(float(data[:-1]) * 1000) , 1)
	else:
		#data = round(int(data) / 1000, 1)
		data = round(int(data), 1)

	return data

iops_dict = {}
cpu_usage_dict = {}

for rr_rw in RW_FLAGS:
	for device in DEVICE_LIST:
		for repeat in range(1, REPEATS + 1):
			for size in BS_LIST:
				for mode in IO_MODE:
					dir = os.path.join(LOG_BASE_DIR, device, rr_rw, f"{size}KB", mode)
					IOPS = getIOPS(dir, repeat)
					CPU = getCPU(dir, repeat)
					key = f"{dir}_{repeat}"

					iops_dict[key] = IOPS
					cpu_usage_dict[key] = CPU

if not os.path.exists(f"./parsed_data"):
    os.system(f"mkdir parsed_data")
    
for rr_rw in RW_FLAGS:
	for device in DEVICE_LIST:
		output_filename = f"./parsed_data/{device}-{rr_rw}-repeat_{REPEATS}.txt"
		f = open(output_filename, "w")
		for repeat in range(1, REPEATS + 1):

			print("IOPS", file=f)
			log_header_print(f)
			for size in BS_LIST:
				for mode in IO_MODE:
					if mode == "INT":
						print(f"{size}".ljust(17), end="", file=f)
					dir = os.path.join(LOG_BASE_DIR, device, rr_rw, f"{size}KB", mode)
					key = f"{dir}_{repeat}"
					print(f"{iops_dict[key]}".ljust(17), end="", file=f)
				print(file=f)
			print("\n",file=f)

			print("CPU", file=f)
			log_header_print(f)
			for size in BS_LIST:
				for mode in IO_MODE:
					if mode == "INT":
						print(f"{size}".ljust(17), end="", file=f)
					dir = os.path.join(LOG_BASE_DIR, device, rr_rw, f"{size}KB", mode)
					key = f"{dir}_{repeat}"
					print(f"{cpu_usage_dict[key]}".ljust(17), end="", file=f)
				print(file=f)
			print("\n", file=f)

		f.close()

		os.system(f"python3 mean_std.py 2 ./parsed_data/{device}-{rr_rw}-repeat_{REPEATS}.txt 1")
