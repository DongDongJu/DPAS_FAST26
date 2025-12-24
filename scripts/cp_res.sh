#!/bin/bash

# Check if the correct number of arguments is provided
if [ $# -lt 2 ]; then
  echo "Usage: $0 [name] <mode list>"
  exit 1
fi

NAME="$1"
MODE_LIST="${@:2}"  # Get the mode list starting from the second argument

# Function to copy the ycsb.txt file for each mode in the mode list
copy_ycsb_results() {
  local mode="$1"
  cp "ycsb_${mode}_results/ycsb.txt" "./result_collection/${NAME}_${mode}.txt"
}

# Check each mode in the mode list and copy the corresponding ycsb.txt file
for mode in $MODE_LIST; do
  case "$mode" in
    "a" | "b" | "c" | "d" | "e" | "f")
      copy_ycsb_results "$mode"
      ;;
    *)
      echo "Unknown mode: $mode"
      exit 1
      ;;
  esac
done

cd result_collection
./parse.sh ${NAME}
#rm ${NAME}*
