#!/usr/bin/env bash

if [ -z "${HMY_PROFILE}" ]; then
  echo "profile is not set, exiting..."
  exit
fi

csv_file="fund-${HMY_PROFILE}.csv"

rm -rf ./bin  # Clear existing CLI, assuption made of where fund.py stores CLI binary.
echo "Getting funding information from harmony.one/keys2"
curl -o "${csv_file}" 'https://docs.google.com/spreadsheets/d/e/2PACX-1vTUUOCAuSgP8TcA1xWY5AbxaMO7OSowYgdvaHpeMQudAZkHkJrf2sGE6TZ0hIbcy20qpZHmlC8HhCw1/pub?gid=0&single=true&output=csv'
python3 -u fund.py --from_csv "${csv_file}" --shards "0" --yes