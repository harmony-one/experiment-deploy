#!/bin/bash
# Simple script for a Jenkins job to hook into
#
# Required Params:
#   CONFIG          A snapshot config as a string in this format: https://github.com/harmony-one/experiment-deploy/blob/master/tools/snapshot/testnet_config.json
#   RCONE_CONFIG    A rclone config as a string following this format: https://docs.harmony.one/home/validators/first-time-setup/using-rclone
#   BUCKET_SYNC     A boolean (true/false) to toggle bucket sync
#
# Optional Params:
#   SSH_KEY         A .pem file used for ssh-ing into configed machines

set -e

echo "=== INSTALLING NEWEST SNAPSHOT SCRIPT ==="
curl -O https://raw.githubusercontent.com/harmony-one/experiment-deploy/master/tools/snapshot/snapshot.py
curl -O https://raw.githubusercontent.com/harmony-one/experiment-deploy/master/tools/snapshot/requirements.txt
python3 -m pip install -r requirements.txt --user
chmod +x snapshot.py
[ ! "$(command -v jq)" ] && echo "jq not installed on machine, exiting" && exit 1
echo "=== FINISHED INSTALL ==="

echo "=== STARTED SETTING UP CONFIG ==="
echo "$CONFIG" > config.json
echo "$RCONE_CONFIG" > "$(jq ".rsync.config_path_on_host" -r < config.json)"
if [ "$(jq ".ssh_key.use_existing_agent" -r < config.json)" == false ]; then
  key_path="$(jq ".ssh_key.path" -r < config.json)"
  [ -n "$SSH_KEY" ] && echo "$SSH_KEY" > "$key_path" && chmod 400 "$key_path"
elif [ -n "$SSH_KEY" ]; then
  echo "SSH_KEY was provided, but config specifies using existing agent. Ignoring provided key..."
fi
echo "=== FINISHED SETTING UP CONFIG ==="

if [ "$BUCKET_SYNC" == true ]; then
  ./snapshot.py --config config.json --bucket-sync
else
  ./snapshot.py --config config.json
fi