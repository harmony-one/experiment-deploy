#!/usr/bin/env bash

if [ -z "${HMY_PROFILE}" ]; then
  echo "profile is not set, exiting..."
  exit
fi

unset OPTARG opt clear force shards
clear=false
force=false
shards="0"
while getopts :cfs:u: opt
do
   case "${opt}" in
    c) clear=true ;;
    f) force=true ;;
    s) shards="${OPTARG}" ;;
    u) csv_source="${OPTARG}" ;;
    *) echo "
        Funding script according to harmony.one/keys2

        Options:
        -c                      Clear the old funding logs before starting the funding process. 
        -f                      Force funding without any checks.
        -s shards CSV string    Specify shards to fund as a CSV string. (default: ${shards})
        -u URL                  Url to the spreadsheet/CSV file that will be used as the source for funding accounts
    "
    exit ;;
   esac
done

csv_file="fund-${HMY_PROFILE}.csv"

if [ -z "${csv_source}" ]; then
  csv_source="https://docs.google.com/spreadsheets/d/e/2PACX-1vTUUOCAuSgP8TcA1xWY5AbxaMO7OSowYgdvaHpeMQudAZkHkJrf2sGE6TZ0hIbcy20qpZHmlC8HhCw1/pub?gid=0&single=true&output=csv"
  csv_name="harmony.one/keys2"
fi

if [ -z "${csv_name}" ]; then
  csv_name=$csv_source
fi

rm -rf ./bin  # Clear existing CLI, assuption made of where fund.py stores CLI binary.
if [ "${clear}" = true ]; then
    echo "[!] clearing old funding logs..."
    rm -rf ./logs/${HMY_PROFILE}/funding.json
fi
echo "[!] getting funding information from ${csv_name}"
curl -o "${csv_file}" "${csv_source}" -s > /dev/null
if [ "${force}" = true ]; then
    echo "[!] force funding..."
    python3 -u fund.py --from_csv "${csv_file}" --shards "${shards}" --yes --force
else
    python3 -u fund.py --from_csv "${csv_file}" --shards "${shards}" --yes 
fi
