#!/bin/bash
# Simple script for a Jenkins job to hook into.
#
# Assumes 'snapshot' is the SSH config for the remote snapshot machine.
# Assumes remote machines has requirements installed.
# Assumes $remote_dir has 'rclone.conf' for testnets and 'snapshot.py'.
# Assumes jenkins machine has jq.
#
# Note that this is only used for testnets.

set -e

remote_dir="\$HOME/snapshot"

unset network machines_path conditions_path OPTIND OPTARG opt
machines_path="./machines.json"
conditions_path="./conditions.json"
network="testnet"
while getopts N:m:c:d: opt; do
  case "${opt}" in
  N) network="${OPTARG}" ;;
  m) machines_path="${OPTARG}" ;;
  c) conditions_path="${OPTARG}" ;;
  *)
    echo "
     Snapshot jenkins job script

     Option:      Help:
     -N <network> Desired Network.
     -m <path>    Path to machines JSON file.
     -c <path>    Path to conditions JSON file.
    "
    exit
    ;;
  esac
done
shift $((${OPTIND} - 1))


# shellcheck disable=SC2016
config_template='{
  "ssh_key": {
    "use_existing_agent": false,
    "path": "~/.ssh/harmony-testnet.pem",
    "passphrase": null
  },
  "machines": <MACHINES>,
  "rsync": {
    "config_path_on_host": "./rclone.conf",
    "config_path_on_client": "$HOME/snapshot_rclone.conf",
    "snapshot_bin": "snapshot:harmony-snapshot/<NETWORK>"
  },
  "condition": <CONDITIONS>,
  "pager_duty": {
    "ignore": true,
    "service_key_v1": null
  }
}'
machines_string=$(cat "$machines_path")
conditions_string=$(cat "$conditions_path")
config=${config_template/<MACHINES>/$machines_string}
config=${config/<CONDITIONS>/$conditions_string}
config=${config/<NETWORK>/$network}

echo "Config for snapshot: $config"
echo "Remote directory for snapshot: '$remote_dir'"

tmp_bash_script_content="#!/bin/bash
echo '$config' > $remote_dir/config.json
cd $remote_dir && ./snapshot.py --config ./config.json --bucket-sync && rm ./config.json
"
echo "$tmp_bash_script_content" | ssh snapshot "bash -s"
