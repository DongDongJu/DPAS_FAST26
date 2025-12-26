#!/bin/bash

# This script contains many 'sudo ...' calls. When run as root (e.g. via run_all.sh),
# make 'sudo' a no-op so we don't depend on sudo configuration or password prompts.
if [[ "${EUID}" -eq 0 ]]; then
  sudo() { "$@"; }
  export -f sudo
fi

# Resolve repo paths (scripts/, apps/, utils/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APPS_DIR="${ROOT_DIR}/apps"
UTILS_DIR="${ROOT_DIR}/utils"

YCSB_CPP_MODI_DIR="${APPS_DIR}/YCSB-cpp-modi"
YCSB_BIN="${YCSB_CPP_MODI_DIR}/ycsb"

ROCKSDB_PROPERTIES_SRC="${YCSB_CPP_MODI_DIR}/rocksdb/rocksdb.properties"
ROCKSDB_PROPERTIES_FILE="${SCRIPT_DIR}/rocksdb.properties.runtime"

# Function to check if a value is a positive integer
is_positive_integer() {
  local value="$1"
  if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
    return 1
  fi
  return 0
}

# Check if there are at least three input parameters
if [ $# -lt 8 ]; then
  echo "Usage: $0 <NUM_OF_THREADS> <NUM_OF_CORES> <DEVICE> <SLEEP_TIME> <IOPS> <EPOCH ms> [MODE1 MODE2 ...]"
  echo "Supported modes: A B C D E F CP LHP EHP DPAS DPAS2 INT"
  echo "Example: $0 2 20 nvme0n1 150 5000 1ms 9ms D A C EHP INT => run 2 threads of ycsb A, C, and D with EHP and INT on 20 cores (sleep time: 150s, 1ms bgio, 9ms idle, 5000 x 2 fio jobs)"
  exit 1
fi

# Initialize variables    set to bgio test 4T3C with 4 io generators
NUM_OF_THREADS=4    # not used. fixed to 4.
NUM_OF_CORES=4	     # not used. fixed to 8 (CPU0: system, 1-3: ycsb, 4-7: io-generator)
DEVICE=$3
SLEEP_TIME=$4
FIO_IOPS=$5
EPOCH=$6
EPOCH=$((${EPOCH}*1000))
BGRUNTIME=$7
THRESHOLD=$8

# Check if N_THREADS and N_CORES are positive integers
if ! is_positive_integer "$NUM_OF_THREADS" || ! is_positive_integer "$NUM_OF_CORES" || ! is_positive_integer "$SLEEP_TIME"; then
  echo "NUM_OF_THREADS, NUM_OF_CORES, and SLEEP_TIME must be positive integers."
  exit 1
fi

# Other variables
OUTPUT="ycsb_output.txt"
OUTPUT_FOLDER="results"
# Use an absolute mount point under this repo to avoid accidental dependency on
# a hardcoded user path inside rocksdb.properties (e.g., /home/shawn/...).
MOUNT_FOLDER="${SCRIPT_DIR}/out"
FILENAME="ycsb.txt"
WORKLORDS_FOLDER="${YCSB_CPP_MODI_DIR}/workloads"
DIR="${MOUNT_FOLDER}"
TMP="$(echo "${DIR}" | sed 's#/#\\/#g')"

# Initialize all workload and mode variables to false
YCSB_A=false
YCSB_B=false
YCSB_C=false
YCSB_D=false
YCSB_E=false
YCSB_F=false
M_CP=false
M_HP=false
M_EHP=false
M_DPAS=false
M_DPAS2=false
M_INT=false

# Function to set a mode variable to true
set_mode() {
  local mode="$1"
  case "$mode" in
    "A") YCSB_A=true ;;
    "B") YCSB_B=true ;;
    "C") YCSB_C=true ;;
    "D") YCSB_D=true ;;
    "E") YCSB_E=true ;;
    "F") YCSB_F=true ;;
    "CP") M_CP=true ;;
    "LHP") M_HP=true ;;
    "EHP") M_EHP=true ;;
    "DPAS") M_DPAS=true ;;
    "DPAS2") M_DPAS2=true ;;
    "INT") M_INT=true ;;
    *) echo "Unknown mode: $mode"; exit 1 ;;
  esac
}

# Process each mode argument starting from the fifth argument
for mode in "${@:9}"; do
  set_mode "$mode"
done

# Display the specified modes
echo "Number of Threads: $NUM_OF_THREADS"
echo "Number of Cores: $NUM_OF_CORES"
echo "Device Name: $DEVICE"
echo "Sleep time: $SLEEP_TIME sec"
echo "IOPS: $FIO_IOPS"
echo "EPOCH: $EPOCH us"
echo "Specified Modes:"
if $YCSB_A; then echo "A"; fi
if $YCSB_B; then echo "B"; fi
if $YCSB_C; then echo "C"; fi
if $YCSB_D; then echo "D"; fi
if $YCSB_E; then echo "E"; fi
if $YCSB_F; then echo "F"; fi
if $M_CP; then echo "CP"; fi
if $M_HP; then echo "LHP"; fi
if $M_EHP; then echo "EHP"; fi
if $M_DPAS; then echo "DPAS"; fi
if $M_DPAS2; then echo "DPAS2"; fi
if $M_INT; then echo "INT"; fi

#echo "sudo bash -c "sudo ./io-generator $DEVICE 128 $FIO_IOPS $EPOCH 1 $SLEEP_TIME 4 EHP" &"
#exit 1


setup_workloads(){
    # Do NOT edit repo-tracked properties in-place. Create a per-run copy.
    cp "${ROCKSDB_PROPERTIES_SRC}" "${ROCKSDB_PROPERTIES_FILE}"
    # Ensure the db directory exists (RocksDB may not mkdir -p parents).
    mkdir -p "${DIR}"
    # Overwrite db path in a robust way (support both keys).
    sed -i \
      -e "s|^rocksdb\\.dbname=.*|rocksdb.dbname=${DIR}|g" \
      -e "s|^dbname=.*|dbname=${DIR}|g" \
      "${ROCKSDB_PROPERTIES_FILE}"
}

reset_device(){
        sudo umount /dev/$DEVICE
        sudo mkfs -t xfs -f /dev/$DEVICE
        sleep 3
        sudo modprobe -r nvme
        sleep 1
        sudo modprobe nvme poll_queues=$NUM_OF_CORES; echo "poll_queue: $NUM_OF_CORES"; # ../../../dump_qmap $DEVICE
        sleep 1
        sudo mount /dev/$DEVICE $MOUNT_FOLDER
        sleep 1
}

reset_mount_folder(){
        sudo rm -rf $MOUNT_FOLDER/*
        sudo umount $MOUNT_FOLDER
        sleep 3
        sudo modprobe -r nvme
        sleep 1
        sudo modprobe nvme poll_queues=$NUM_OF_CORES; echo "poll_queue: $NUM_OF_CORES"; # ../../../dump_qmap $DEVICE
        sleep 1
        sudo mount /dev/$DEVICE $MOUNT_FOLDER
        sleep 1
}
reset_mount_folder_int(){
        sudo rm -rf $MOUNT_FOLDER/*
        sudo umount $MOUNT_FOLDER
        sleep 3
        sudo modprobe -r nvme
        sleep 1
        sudo modprobe nvme poll_queues=0; echo "poll_queue: 0"; # ../../../dump_qmap $DEVICE
        sleep 1
        sudo mount /dev/$DEVICE $MOUNT_FOLDER
        sleep 1
}

kill_bg_ios(){
        sudo kill -9 $(pgrep io-generator1) 2>/dev/null
        sudo kill -9 $(pgrep io-generator2) 2>/dev/null
        sudo kill -9 $(pgrep io-generator3) 2>/dev/null
        sudo kill -9 $(pgrep io-generator4) 2>/dev/null
}

setup_workloads

ycsb_run(){
    LOGS_FOLDER="ycsb_$1_results"
    workload_file="${YCSB_CPP_MODI_DIR}/workloads/workload$1"

    [ ! -d $OUTPUT_FOLDER ] && mkdir $OUTPUT_FOLDER

    if [ -d $OUTPUT_FOLDER ]
    then
        rm -rf $OUTPUT_FOLDER/*
    else
        mkdir $OUTPUT_FOLDER
    fi

    [ -f $FILENAME ] && rm -f $FILENAME

    if [ -d $LOGS_FOLDER ]
    then
        rm -rf $LOGS_FOLDER/*
    else
        mkdir $LOGS_FOLDER
    fi

    # Unmount the tested device and remove mount folder
    if findmnt --source "/dev/${DEVICE}" >/dev/null 2>&1; then
      echo "unmount /dev/${DEVICE}"
      sudo umount "/dev/${DEVICE}" || true
    fi
    [ -d "${MOUNT_FOLDER}" ] && sudo rm -rf "${MOUNT_FOLDER}"

    # Create mount point
    mkdir -p "${MOUNT_FOLDER}"
    echo "initialization"
    sudo mkfs -t xfs -f /dev/$DEVICE
    sleep 3
    sudo modprobe -r nvme
    sleep 3
    sudo modprobe nvme poll_queues=$NUM_OF_CORES; echo "poll_queue: $NUM_OF_CORES"; # ../../../dump_qmap $DEVICE
    sleep 1
    sudo mount "/dev/${DEVICE}" "${MOUNT_FOLDER}"
    sleep 1


    # run CP
    if $M_CP; then 
        (cd "${YCSB_CPP_MODI_DIR}" && "${YCSB_BIN}" -load -db rocksdb -P "${workload_file}" -P "${ROCKSDB_PROPERTIES_FILE}" -s)
        # sudo bash -c "cd filebench_modi && ./filebench -f workloads/videoserver_init.f"
	echo "wait $SLEEP_TIME sec for NAND SSD"; sleep $SLEEP_TIME;
        echo "enable polling and clear page cache before benchmarking"
        sudo bash -c "echo -1 > /sys/block/$DEVICE/queue/io_poll_delay"
            sudo bash -c "echo 1 > /sys/block/$DEVICE/queue/nomerges"
            sleep 3
        sudo bash -c "sync; echo 3 > /proc/sys/vm/drop_caches"
        echo "io_poll, io_poll_delay, pas_enabled, ehp_enabled"
        cat /sys/block/$DEVICE/queue/io_poll
        cat /sys/block/$DEVICE/queue/io_poll_delay
        cat /sys/block/$DEVICE/queue/pas_enabled    
        cat /sys/block/$DEVICE/queue/ehp_enabled    
        sudo bash -c "sudo ./io-generator1 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 CP" &
        sudo bash -c "sudo ./io-generator2 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 CP" &
        sudo bash -c "sudo ./io-generator3 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 CP" &
        sudo bash -c "sudo ./io-generator4 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 CP" &
        (cd "${YCSB_CPP_MODI_DIR}" && "${YCSB_BIN}" -run -db rocksdb -P "${workload_file}" -P "${ROCKSDB_PROPERTIES_FILE}" -p threadcount=$NUM_OF_THREADS -s) | tee $OUTPUT &  
	while true; do
        if ps aux | grep -v grep | grep "ycsb" > /dev/null; then
            echo "ycsb found."
            break
        else
            echo "ycbs not found. Waiting..."
            sleep 0.05
        fi
        done
        bash "${UTILS_DIR}/track_cpu.sh" ycsb cpu_single_workload.txt 
        echo "clean up"
        kill_bg_ios
        [ ! -d $OUTPUT_FOLDER ] && mkdir $OUTPUT_FOLDER     
        mv $OUTPUT $OUTPUT_FOLDER/
        [ -f results.txt ] && rm -f results.txt
        echo "CP" >> results.txt
        python3 "${UTILS_DIR}/postprocessing.py"
        cat results.txt >> $FILENAME
        mv cpu_single_workload.txt "$OUTPUT_FOLDER/cpu_polling.txt"
        mv $OUTPUT_FOLDER "$LOGS_FOLDER/polling"
    fi

    # run LHP
    if $M_HP; then 
        reset_mount_folder
        (cd "${YCSB_CPP_MODI_DIR}" && "${YCSB_BIN}" -load -db rocksdb -P "${workload_file}" -P "${ROCKSDB_PROPERTIES_FILE}" -s)
	echo "wait $SLEEP_TIME sec for NAND SSD"; sleep $SLEEP_TIME;
        echo "enable hybrid-polling and clear page cache before benchmarking"
        sudo bash -c "echo 0 > /sys/block/$DEVICE/queue/pas_enabled"
        sudo bash -c "echo 0 > /sys/block/$DEVICE/queue/io_poll_delay"
        sudo bash -c "echo 1 > /sys/block/$DEVICE/queue/nomerges"
        sleep 3
        sudo bash -c "sync; echo 3 > /proc/sys/vm/drop_caches"
        echo "io_poll, io_poll_delay, pas_enabled, ehp_enabled"
        cat /sys/block/$DEVICE/queue/io_poll
        cat /sys/block/$DEVICE/queue/io_poll_delay
        cat /sys/block/$DEVICE/queue/pas_enabled    
        cat /sys/block/$DEVICE/queue/ehp_enabled    
        sudo bash -c "sudo ./io-generator1 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 LHP" &
        sudo bash -c "sudo ./io-generator2 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 LHP" &
        sudo bash -c "sudo ./io-generator3 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 LHP" &
        sudo bash -c "sudo ./io-generator4 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 LHP" &
        (cd "${YCSB_CPP_MODI_DIR}" && "${YCSB_BIN}" -run -db rocksdb -P "${workload_file}" -P "${ROCKSDB_PROPERTIES_FILE}" -s -p threadcount=$NUM_OF_THREADS) | tee $OUTPUT &  
	while true; do
        if ps aux | grep -v grep | grep "ycsb" > /dev/null; then
            echo "ycsb found."
            break
        else
            echo "ycbs not found. Waiting..."
            sleep 0.05
        fi
        done
        bash "${UTILS_DIR}/track_cpu.sh" ycsb cpu_single_workload.txt 
        echo "clean up"
        kill_bg_ios
        [ ! -d $OUTPUT_FOLDER ] && mkdir $OUTPUT_FOLDER     
        mv $OUTPUT $OUTPUT_FOLDER/
        [ -f results.txt ] && rm -f results.txt
        echo "LHP" >> results.txt
        python3 "${UTILS_DIR}/postprocessing.py"
        cat results.txt >> $FILENAME
        mv cpu_single_workload.txt "$OUTPUT_FOLDER/cpu_hybrid_polling.txt"
        mv $OUTPUT_FOLDER "$LOGS_FOLDER/hybrid-polling"
    fi

    # run EHP
    if $M_EHP; then 
        reset_mount_folder
        (cd "${YCSB_CPP_MODI_DIR}" && "${YCSB_BIN}" -load -db rocksdb -P "${workload_file}" -P "${ROCKSDB_PROPERTIES_FILE}" -s)
	echo "wait $SLEEP_TIME sec for NAND SSD"; sleep $SLEEP_TIME;
        echo "enable EHP and clear page cache before benchmarking"
        sudo bash -c "echo 1 > /sys/block/$DEVICE/queue/ehp_enabled"
        sudo bash -c "echo 0 > /sys/block/$DEVICE/queue/io_poll_delay"
        sudo bash -c "echo 1 > /sys/block/$DEVICE/queue/nomerges"
        sleep 3
        sudo bash -c "sync; echo 3 > /proc/sys/vm/drop_caches"
        echo "io_poll, io_poll_delay, pas_enabled, ehp_enabled"
        cat /sys/block/$DEVICE/queue/io_poll
        cat /sys/block/$DEVICE/queue/io_poll_delay
        cat /sys/block/$DEVICE/queue/pas_enabled    
        cat /sys/block/$DEVICE/queue/ehp_enabled    
        sudo bash -c "sudo ./io-generator1 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 EHP" &
        sudo bash -c "sudo ./io-generator2 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 EHP" &
        sudo bash -c "sudo ./io-generator3 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 EHP" &
        sudo bash -c "sudo ./io-generator4 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 EHP" &
        (cd "${YCSB_CPP_MODI_DIR}" && "${YCSB_BIN}" -run -db rocksdb -P "${workload_file}" -P "${ROCKSDB_PROPERTIES_FILE}" -s -p threadcount=$NUM_OF_THREADS) | tee $OUTPUT &
	while true; do
        if ps aux | grep -v grep | grep "ycsb" > /dev/null; then
            echo "ycsb found."
            break
        else
            echo "ycbs not found. Waiting..."
            sleep 0.05
        fi
        done
        bash "${UTILS_DIR}/track_cpu.sh" ycsb cpu_single_workload.txt 
        echo "clean up"
        kill_bg_ios
        sudo bash -c "echo 0 > /sys/block/$DEVICE/queue/ehp_enabled"
        [ ! -d $OUTPUT_FOLDER ] && mkdir $OUTPUT_FOLDER     
        mv $OUTPUT $OUTPUT_FOLDER/
        [ -f results.txt ] && rm -f results.txt
        echo "EHP" >> results.txt
        python3 "${UTILS_DIR}/postprocessing.py"
        cat results.txt >> $FILENAME
        mv cpu_single_workload.txt "$OUTPUT_FOLDER/cpu_ehp.txt"
        mv $OUTPUT_FOLDER "$LOGS_FOLDER/ehp"
    fi

    # run DPAS
    if $M_DPAS; then 
        reset_mount_folder
        (cd "${YCSB_CPP_MODI_DIR}" && "${YCSB_BIN}" -load -db rocksdb -P "${workload_file}" -P "${ROCKSDB_PROPERTIES_FILE}" -s)
	echo "wait $SLEEP_TIME sec for NAND SSD"; sleep $SLEEP_TIME;
        echo "enable DPAS and clear page cache before benchmarking"
        sudo bash -c "echo 1 > /sys/block/$DEVICE/queue/pas_enabled"
        sudo bash -c "echo 1 > /sys/block/$DEVICE/queue/pas_adaptive_enabled"
        sudo bash -c "echo 0 > /sys/block/$DEVICE/queue/io_poll_delay"
        sudo bash -c "echo 1 > /sys/block/$DEVICE/queue/nomerges"
	sleep 3
        sudo bash -c "sync; echo 3 > /proc/sys/vm/drop_caches"
        echo "io_poll, io_poll_delay, pas_enabled, ehp_enabled"
        cat /sys/block/$DEVICE/queue/io_poll
        cat /sys/block/$DEVICE/queue/io_poll_delay
        cat /sys/block/$DEVICE/queue/pas_enabled    
        cat /sys/block/$DEVICE/queue/ehp_enabled    
        sudo bash -c "sudo ./io-generator1 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 DPAS" &
        sudo bash -c "sudo ./io-generator2 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 DPAS" &
        sudo bash -c "sudo ./io-generator3 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 DPAS" &
        sudo bash -c "sudo ./io-generator4 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 DPAS" &
        (cd "${YCSB_CPP_MODI_DIR}" && "${YCSB_BIN}" -run -db rocksdb -P "${workload_file}" -P "${ROCKSDB_PROPERTIES_FILE}" -s -p threadcount=$NUM_OF_THREADS) | tee $OUTPUT &
	while true; do
        if ps aux | grep -v grep | grep "ycsb" > /dev/null; then
            echo "ycsb found."
            break
        else
            echo "ycbs not found. Waiting..."
            sleep 0.05
        fi
        done
        bash "${UTILS_DIR}/track_cpu.sh" ycsb cpu_single_workload.txt 
        echo "clean up"
        kill_bg_ios
        sudo bash -c "echo 0 > /sys/block/$DEVICE/queue/pas_enabled"
        [ ! -d $OUTPUT_FOLDER ] && mkdir $OUTPUT_FOLDER     
        mv $OUTPUT $OUTPUT_FOLDER/
        [ -f results.txt ] && rm -f results.txt
        echo "PAS" >> results.txt
        python3 "${UTILS_DIR}/postprocessing.py"
        cat results.txt >> $FILENAME
        mv cpu_single_workload.txt "$OUTPUT_FOLDER/cpu_dpas.txt"
        mv $OUTPUT_FOLDER "$LOGS_FOLDER/dpas"
    fi

    # run DPAS2
    if $M_DPAS2; then 
        reset_mount_folder
        (cd "${YCSB_CPP_MODI_DIR}" && "${YCSB_BIN}" -load -db rocksdb -P "${workload_file}" -P "${ROCKSDB_PROPERTIES_FILE}" -s)
	dmesg -c > tmp.log
	echo "wait $SLEEP_TIME sec for NAND SSD"; sleep $SLEEP_TIME;
        echo "enable DPAS2 and clear page cache before benchmarking"
        sudo bash -c "echo 1 > /sys/block/$DEVICE/queue/pas_enabled"
        sudo bash -c "echo 1 > /sys/block/$DEVICE/queue/pas_adaptive_enabled"
        sudo bash -c "echo 0 > /sys/block/$DEVICE/queue/io_poll_delay"
        sudo bash -c "echo 1 > /sys/block/$DEVICE/queue/nomerges"
	sudo bash -c "echo 1 > /sys/block/$DEVICE/queue/switch_enabled" 
	sudo bash -c "echo 0 > /sys/block/$DEVICE/queue/switch_param1" 
	sudo bash -c "echo 10 > /sys/block/$DEVICE/queue/switch_param2" 
	sudo bash -c "echo $THRESHOLD > /sys/block/$DEVICE/queue/switch_param3" 
	sudo bash -c "echo 1 > /sys/block/$DEVICE/queue/switch_param4" 
	sleep 3
        sudo bash -c "sync; echo 3 > /proc/sys/vm/drop_caches"
        echo "io_poll, io_poll_delay, pas_enabled, ehp_enabled"
        cat /sys/block/$DEVICE/queue/io_poll
        cat /sys/block/$DEVICE/queue/io_poll_delay
        cat /sys/block/$DEVICE/queue/pas_enabled    
        cat /sys/block/$DEVICE/queue/ehp_enabled    
        sudo bash -c "sudo ./io-generator1 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 DPAS2" &
        sudo bash -c "sudo ./io-generator2 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 DPAS2" &
        sudo bash -c "sudo ./io-generator3 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 DPAS2" &
        sudo bash -c "sudo ./io-generator4 $DEVICE 128 $FIO_IOPS $EPOCH 1 $BGRUNTIME 1 DPAS2" &
        (cd "${YCSB_CPP_MODI_DIR}" && "${YCSB_BIN}" -run -db rocksdb -P "${workload_file}" -P "${ROCKSDB_PROPERTIES_FILE}" -s -p threadcount=$NUM_OF_THREADS) | tee $OUTPUT &
	while true; do
        if ps aux | grep -v grep | grep "ycsb" > /dev/null; then
            echo "ycsb found."
            break
        else
            echo "ycbs not found. Waiting..."
            sleep 0.05
        fi
        done
        bash "${UTILS_DIR}/track_cpu.sh" ycsb cpu_single_workload.txt 
        echo "clean up"
        kill_bg_ios
        sudo bash -c "echo 0 > /sys/block/$DEVICE/queue/pas_enabled"
        [ ! -d $OUTPUT_FOLDER ] && mkdir $OUTPUT_FOLDER     
        mv $OUTPUT $OUTPUT_FOLDER/
        [ -f results.txt ] && rm -f results.txt
        echo "DPAS" >> results.txt
        python3 "${UTILS_DIR}/postprocessing.py"
        cat results.txt >> $FILENAME
	cat /sys/block/nvme1n1/queue/switch_stat
	dmesg -c 
        mv cpu_single_workload.txt "$OUTPUT_FOLDER/cpu_dpas2.txt"
        mv $OUTPUT_FOLDER "$LOGS_FOLDER/dpas2"
    fi
    # run INT
    if $M_INT; then 
        reset_mount_folder_int
        (cd "${YCSB_CPP_MODI_DIR}" && "${YCSB_BIN}" -load -db rocksdb -P "${workload_file}" -P "${ROCKSDB_PROPERTIES_FILE}" -s)
	echo "wait $SLEEP_TIME sec for NAND SSD"; sleep $SLEEP_TIME;
        echo "enable interrupt clear page cache before benchmarking"
        sudo bash -c "echo 1 > /sys/block/$DEVICE/queue/nomerges"
        sleep 3
        sudo bash -c "sync; echo 3 > /proc/sys/vm/drop_caches"
        echo "io_poll, io_poll_delay, pas_enabled, ehp_enabled"
        cat /sys/block/$DEVICE/queue/io_poll
        cat /sys/block/$DEVICE/queue/io_poll_delay
        cat /sys/block/$DEVICE/queue/pas_enabled    
        cat /sys/block/$DEVICE/queue/ehp_enabled    
        sudo bash -c "sudo ./io-generator1 $DEVICE 128 $FIO_IOPS $EPOCH 0 $BGRUNTIME 1 INT" &
        sudo bash -c "sudo ./io-generator2 $DEVICE 128 $FIO_IOPS $EPOCH 0 $BGRUNTIME 1 INT" &
        sudo bash -c "sudo ./io-generator3 $DEVICE 128 $FIO_IOPS $EPOCH 0 $BGRUNTIME 1 INT" &
        sudo bash -c "sudo ./io-generator4 $DEVICE 128 $FIO_IOPS $EPOCH 0 $BGRUNTIME 1 INT" &
        (cd "${YCSB_CPP_MODI_DIR}" && "${YCSB_BIN}" -run -db rocksdb -P "${workload_file}" -P "${ROCKSDB_PROPERTIES_FILE}" -s -p threadcount=$NUM_OF_THREADS) | tee $OUTPUT &
	while true; do
        if ps aux | grep -v grep | grep "ycsb" > /dev/null; then
            echo "ycsb found."
            break
        else
            echo "ycbs not found. Waiting..."
            sleep 0.05
        fi
        done
        bash "${UTILS_DIR}/track_cpu.sh" ycsb cpu_single_workload.txt 
        echo "clean up"
        kill_bg_ios
        [ ! -d $OUTPUT_FOLDER ] && mkdir $OUTPUT_FOLDER     
        mv $OUTPUT $OUTPUT_FOLDER/
        [ -f results.txt ] && rm -f results.txt
        echo "INT" >> results.txt
        python3 "${UTILS_DIR}/postprocessing.py"
        cat results.txt >> $FILENAME
        mv cpu_single_workload.txt "$OUTPUT_FOLDER/cpu_interrupt.txt"
        mv $OUTPUT_FOLDER "$LOGS_FOLDER/interrupt"
    fi

    mv $FILENAME $LOGS_FOLDER/
    rm -rf $OUTPUT_FOLDER
    rm -f results.txt
}

if $YCSB_A; then echo "YCSB_A"; ycsb_run a; fi
if $YCSB_B; then echo "YCSB_B"; ycsb_run b; fi
if $YCSB_C; then echo "YCSB_C"; ycsb_run c; fi
if $YCSB_D; then echo "YCSB_D"; ycsb_run d; fi
if $YCSB_E; then echo "YCSB_E"; ycsb_run e; fi
if $YCSB_F; then echo "YCSB_F"; ycsb_run f; fi

