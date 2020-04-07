#!/usr/bin/env bash

if [ -z "${HMY_PROFILE}" ]; then
  echo "profile is not set, exiting..."
  exit
fi

csv_source="https://docs.google.com/spreadsheets/d/e/2PACX-1vTUUOCAuSgP8TcA1xWY5AbxaMO7OSowYgdvaHpeMQudAZkHkJrf2sGE6TZ0hIbcy20qpZHmlC8HhCw1/pub?gid=0&single=true&output=csv"
csv_file="fund-${HMY_PROFILE}.csv"

unset OPTARG opt clear force shards
clear=false
force=false
shards="0"
while getopts :cfs: opt
do
   case "${opt}" in
    c) clear=true ;;
    f) force=true ;;
    s) shards="${OPTARG}" ;;
    *) echo "
        Funding script according to harmony.one/keys2

        Options:
        -c                      Clear the old funding logs before starting the funding process. 
        -f                      Force funding without any checks.
        -s shards CSV string    Specify shards to fund as a CSV string. (default: ${shards})
    "
    exit ;;
   esac
done

rm -rf ./bin  # Clear existing CLI, assuption made of where fund.py stores CLI binary.
if [ "${clear}" = true ]; then
    echo "[!] clearing old funding logs..."
    rm ./logs/${HMY_PROFILE}/funding.json
fi
echo "[!] getting funding information from harmony.one/keys2"
curl -o "${csv_file}" "${csv_source}" -s > /dev/null
if [ "${force}" = true ]; then
    echo "[!] force funding..."
    python3 -u fund.py --from_csv "${csv_file}" --shards "${shards}" --yes --force
else
    python3 -u fund.py --from_csv "${csv_file}" --shards "${shards}" --yes 
fi