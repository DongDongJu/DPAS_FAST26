#!/bin/bash

if [ $# -ne 2 ]; then
	echo "Usage: $0 [0/1] [core range 1 to X] (1<=X<=19)"
  exit 1
fi

# Get the action and core number from the arguments
action="$1"
core_number="$2"

# Check if the core number is within the valid range (1 to 19)
if [ "$core_number" -lt 0 ] || [ "$core_number" -gt 20 ]; then
  echo "Invalid core number: $core_number (Core number should be between 1 and 19)."
  exit 1
fi

# Perform the specified action on the selected cores
for ((i = 1; i <= core_number; i++)); do
  ./cpus.sh $1 $i
done

