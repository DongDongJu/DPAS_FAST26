#!/bin/bash

# Receive the NVMe drive name from the user
DEVICE_NAME=$1

if [[ -z "$DEVICE_NAME" ]]; then
    echo "Please input the NVMe drive name as a parameter."
    exit 1
fi

# Check if the specified drive exists
if ! ls /dev/${DEVICE_NAME} &>/dev/null; then
    echo "Drive /dev/${DEVICE_NAME} cannot be found."
    exit 1
fi

# Format the drive with XFS file system
mkfs.xfs -f /dev/${DEVICE_NAME}

# Create the directory for mounting
mkdir -p ./test

# Mount the formatted drive
mount /dev/${DEVICE_NAME} ./test

# Run the fio test
PRERUN_RUNTIME="${DPAS_PRERUN_RUNTIME:-60}"
fio --name prerun --directory=./test --ioengine=sync --filename_format=testfile.\$jobnum --rw=randwrite --bs=4k --size=100m --numjobs=32 --runtime="${PRERUN_RUNTIME}" --group_reporting

# Unmount the drive
umount ./test

# Print result message
echo "The test has completed and the drive ${DEVICE_NAME} has been unmounted."
