#!/bin/bash
#
# Extract ops/sec and cpu values from cp_res.sh-collected files.
#
# Usage:
#   ./parse.sh <PREFIX>
# Example:
#   ./parse.sh MACRO_P41

set -euo pipefail

prefix="${1:-}"
if [[ -z "${prefix}" ]]; then
  echo "Usage: $0 <PREFIX>" >&2
  exit 2
fi

cat "${prefix}"* | grep -e ops | grep -oE '[0-9]+(\.[0-9]+)?$'
echo --
cat "${prefix}"* | grep -e cpu | grep -oE '[0-9]+(\.[0-9]+)?$'

