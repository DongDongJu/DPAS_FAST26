#!/bin/bash

DEVICES=("nvme0n1" "nvme1n1" "nvme2n1")
IO_MODE=("CP" "HP" "EHP" "PAS" "DPAS" "INT")
BS_SIZE=("8" "16" "32" "64" "128")
RR_RW=("RR") 
REPEATS=(1)
MAX_CORE=4
RUNTIME="${DPAS_RUNTIME:-10}"

# Optional overrides (comma-separated)
if [[ -n "${DPAS_DEVICE_LIST:-}" ]]; then
	IFS=',' read -r -a DEVICES <<< "${DPAS_DEVICE_LIST}"
fi
if [[ -n "${DPAS_IO_MODE:-}" ]]; then
	IFS=',' read -r -a IO_MODE <<< "${DPAS_IO_MODE}"
fi
if [[ -n "${DPAS_BS_LIST:-}" ]]; then
	IFS=',' read -r -a BS_SIZE <<< "${DPAS_BS_LIST}"
fi

SLEEP_DROP="${DPAS_SLEEP_DROP:-5}"
SLEEP_AFTER_RUN="${DPAS_SLEEP_AFTER_RUN:-3}"
SLEEP_AFTER_MODPROBE="${DPAS_SLEEP_AFTER_MODPROBE:-5}"
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
        for size in "${BS_SIZE[@]}"; do
            	for mode in "${IO_MODE[@]}"; do
            for device in "${DEVICES[@]}"; do
                    mkdir -p ./fio_data/${device}/${rr_rw}/${size}KB/${mode}
                    echo 3 > /proc/sys/vm/drop_caches
                    sleep "${SLEEP_DROP}"

                    FIO_CMD="fio --directory=./test_${device} --filename_format=testfile.\$jobnum --ramp_time=3 --idle-prof=system --size=100m --direct=1 --bs=${size}k --ioengine=pvsync2 --iodepth=1 --runtime=${RUNTIME} --numjobs=1 --time_based --group_reporting --name=run --eta-newline=1 --cpus_allowed=${CPU_ALLOWED_LIST} --cpus_allowed_policy=split --nice=-10 --prioclass=2 --prio=0"
                    CP_FIO_CMD="fio --directory=./test_${device} --filename_format=testfile.\$jobnum --ramp_time=3 --size=100m --direct=1 --bs=${size}k --ioengine=pvsync2 --iodepth=1 --runtime=${RUNTIME} --numjobs=20 --time_based --group_reporting --name=run --eta-newline=1 --nice=-10 --prioclass=2 --prio=0"

                    if [ ${rr_rw} == "RR" ]; then
                        FIO_CMD="${FIO_CMD} --readonly --rw=randread"
                    else
                        FIO_CMD="${FIO_CMD} --rw=randwrite"
                    fi

			if [ ${device} == "nvme0n1" ]; then
				THRESHOLD="10"
			elif [ ${device} == "nvme1n1" ]; then
				THRESHOLD="30"
			elif [ ${device} == "nvme2n1" ]; then
				THRESHOLD="10"
			fi

                    if [ ${mode} != "INT" ]; then
                        FIO_CMD="${FIO_CMD} --hipri"
                    fi

                    if [ ${mode} == "INT" ]; then
                        modprobe -r nvme && modprobe nvme
                        sleep "${SLEEP_AFTER_MODPROBE}"
			echo 0 > /sys/block/${device}/queue/nomerges
                    elif [ ${mode} == "CP" ]; then
                        modprobe -r nvme && modprobe nvme poll_queues=${MAX_CORE}
                        sleep "${SLEEP_AFTER_MODPROBE}"
			echo 0 > /sys/block/${device}/queue/nomerges
                    elif [ ${mode} == "HP" ]; then
                        modprobe -r nvme && modprobe nvme poll_queues=${MAX_CORE}
                        sleep "${SLEEP_AFTER_MODPROBE}"
                        echo 0 > /sys/block/${device}/queue/io_poll_delay
			echo 0 > /sys/block/${device}/queue/nomerges
                    elif [ ${mode} == "EHP" ]; then
                        modprobe -r nvme && modprobe nvme poll_queues=${MAX_CORE}
                        sleep "${SLEEP_AFTER_MODPROBE}"
                        echo 0 > /sys/block/${device}/queue/io_poll_delay
                        echo 1 > /sys/block/${device}/queue/ehp_enabled
			echo 0 > /sys/block/${device}/queue/nomerges
                    elif [ ${mode} == "PAS" ]; then
                        modprobe -r nvme && modprobe nvme poll_queues=${MAX_CORE}
                        sleep "${SLEEP_AFTER_MODPROBE}"
                        echo 0 > /sys/block/${device}/queue/io_poll_delay
                        echo 1 > /sys/block/${device}/queue/pas_enabled
                        echo 1 > /sys/block/${device}/queue/pas_adaptive_enabled
			echo 0 > /sys/block/${device}/queue/nomerges
			echo 0 > /sys/block/${device}/queue/switch_enabled
                    elif [ ${mode} == "DPAS" ]; then
                        modprobe -r nvme && modprobe nvme poll_queues=${MAX_CORE}
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
                    
                    echo ${device} "repeat"${repeat} ${mode} ${size}KB ${rr_rw}

		    mount /dev/${device} test_${device}
		    #${FIO_CMD}
			if [[ "${DPAS_DRAFT:-0}" != "1" ]] && [ ${device} == "nvme1n1" ] && [ ${mode} == "CP" ]; then
			    ${FIO_CMD}; ${FIO_CMD};
		fi
		  # ${FIO_CMD}
                    ${FIO_CMD} > ./fio_data/${device}/${rr_rw}/${size}KB/${mode}/fio_report_${repeat}.log
		    umount /dev/${device}
                    sleep "${SLEEP_AFTER_RUN}"
                done    
            done
        done
    done
done

echo `date`
