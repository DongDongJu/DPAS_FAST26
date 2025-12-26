#!/bin/bash

DEVICES=("nvme0n1" "nvme1n1" "nvme2n1")
IO_MODE=("DPAS" "PAS" "LHP" "EHP" "CP" "INT")
JOBS=(20 16 8 4 2 1)
RR_RW=("RR")
REPEATS=(1)
MAX_CORE=20
RUNTIME="${DPAS_RUNTIME:-10}"

# Optional overrides (comma-separated)
if [[ -n "${DPAS_DEVICE_LIST:-}" ]]; then
  IFS=',' read -r -a DEVICES <<< "${DPAS_DEVICE_LIST}"
fi
if [[ -n "${DPAS_IO_MODE:-}" ]]; then
  IFS=',' read -r -a IO_MODE <<< "${DPAS_IO_MODE}"
fi
if [[ -n "${DPAS_JOB_LIST:-}" ]]; then
  IFS=',' read -r -a JOBS <<< "${DPAS_JOB_LIST}"
fi

SLEEP_DROP="${DPAS_SLEEP_DROP:-1}"
SLEEP_AFTER_RUN="${DPAS_SLEEP_AFTER_RUN:-1}"
SLEEP_AFTER_MODPROBE="${DPAS_SLEEP_AFTER_MODPROBE:-1}"
SLEEP_AFTER_UMOUNT="${DPAS_SLEEP_AFTER_UMOUNT:-1}"

# Avoid "fio: fio_setaffinity failed" by using the CPUs actually allowed
# for this process (honors cpuset/cgroup constraints).
CPU_ALLOWED_LIST="$(awk -F: '/Cpus_allowed_list/ {gsub(/^[ \t]+/, "", $2); print $2}' /proc/self/status || true)"
if [[ -z "${CPU_ALLOWED_LIST}" ]]; then
  CPU_ALLOWED_LIST="0-$(( $(nproc --all) - 1 ))"
fi

pushd ../
./xfs_fio_prerun.sh nvme2n1
./xfs_fio_prerun.sh nvme1n1
./xfs_fio_prerun.sh nvme0n1
popd

for device in "${DEVICES[@]}"; do
	mkdir -p test_${device}
	umount /dev/${device}
	sleep "${SLEEP_AFTER_UMOUNT}"
done

echo `date`

for rr_rw in "${RR_RW[@]}"; do
    for repeat in "${REPEATS[@]}"; do
        for job in "${JOBS[@]}"; do
		for device in "${DEVICES[@]}"; do
		    for mode in "${IO_MODE[@]}"; do

                    mkdir -p ./fio_data/${device}/${rr_rw}/${job}T/${mode}
                    echo 3 > /proc/sys/vm/drop_caches
                    sleep "${SLEEP_DROP}"

                    FIO_CMD="fio --directory=./test_${device} --filename_format=testfile.\$jobnum --direct=1 --ramp_time=3 --size=100m --bs=4k --ioengine=pvsync2 --iodepth=1 --runtime=${RUNTIME} --numjobs=${job} --time_based --group_reporting --name=run --eta-newline=1 --cpus_allowed=${CPU_ALLOWED_LIST} --cpus_allowed_policy=split --nice=-10 --prioclass=2 --prio=0"

                    if [ ${rr_rw} == "RR" ]; then
                        FIO_CMD="${FIO_CMD} --readonly --rw=randread"
                    else
                        FIO_CMD="${FIO_CMD} --rw=randwrite"
                        if [ ${device} == "983" ]; then
                            sleep 5
                        fi
                    fi

		    if [ ${device} == "nvme1n1" ]; then  # theta := 3 for Optane 5800X (10X) 
				THRESHOLD="30"
			else
				THRESHOLD="10" # theta :=1 for NAND SSDs (10X)
			fi


                    if [ ${mode} != "INT" ]; then
                        FIO_CMD="${FIO_CMD} --hipri"
                    fi
                    if [ ${mode} == "INT" ]; then
                        modprobe -r nvme && modprobe nvme
                        sleep "${SLEEP_AFTER_MODPROBE}"
                        echo 0 > /sys/block/${device}/queue/nomerges
                    elif [ ${mode} == "CP" ]; then
                        modprobe -r nvme && modprobe nvme poll_queues=${JOBS}
                        sleep "${SLEEP_AFTER_MODPROBE}"
                        echo 0 > /sys/block/${device}/queue/nomerges
                    elif [ ${mode} == "LHP" ]; then
                        modprobe -r nvme && modprobe nvme poll_queues=${JOBS}
                        sleep "${SLEEP_AFTER_MODPROBE}"
                        echo 0 > /sys/block/${device}/queue/io_poll_delay
                        echo 0 > /sys/block/${device}/queue/nomerges
                    elif [ ${mode} == "EHP" ]; then
			modprobe -r nvme && modprobe nvme poll_queues=${JOBS}
			sleep "${SLEEP_AFTER_MODPROBE}"
                        echo 0 > /sys/block/${device}/queue/io_poll_delay
                        echo 1 > /sys/block/${device}/queue/ehp_enabled
                        echo 0 > /sys/block/${device}/queue/nomerges
                    elif [ ${mode} == "PAS" ]; then
                        modprobe -r nvme && modprobe nvme poll_queues=${JOBS}
                        sleep "${SLEEP_AFTER_MODPROBE}"
                        echo 0 > /sys/block/${device}/queue/io_poll_delay
                        echo 1 > /sys/block/${device}/queue/pas_enabled
                        echo 1 > /sys/block/${device}/queue/pas_adaptive_enabled
                        echo 0 > /sys/block/${device}/queue/nomerges
			echo 0 > /sys/block/${device}/queue/switch_enabled
                    elif [ ${mode} == "DPAS" ]; then
                        modprobe -r nvme && modprobe nvme poll_queues=${JOBS}
                        sleep "${SLEEP_AFTER_MODPROBE}"
                        echo 0 > /sys/block/${device}/queue/io_poll_delay
                        echo 0 > /sys/block/${device}/queue/nomerges
                        echo 1 > /sys/block/${device}/queue/pas_enabled
                        echo 1 > /sys/block/${device}/queue/pas_adaptive_enabled
			echo 1 > /sys/block/${device}/queue/switch_enabled
			echo 0 > /sys/block/${device}/queue/switch_param1
			echo 10 > /sys/block/${device}/queue/switch_param2
			echo ${THRESHOLD} > /sys/block/${device}/queue/switch_param3
			echo 1 > /sys/block/${device}/queue/switch_param4
                    fi
		    mount /dev/${device} test_${device}
                    echo ${device} "repeat"${repeat} ${mode} ${job}T ${rr_rw}
                    ${FIO_CMD} > ./fio_data/${device}/${rr_rw}/${job}T/${mode}/fio_report_${repeat}.log
		    umount /dev/${device}
		    sleep "${SLEEP_AFTER_RUN}"

                done
            done
        done
    done
done



for device in "${DEVICES[@]}"; do
	umount test_${device}
done
echo `date`

