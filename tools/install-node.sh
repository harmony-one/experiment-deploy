#!/usr/bin/env bash

# This script installs a harmony node (for internally ran nodes).
# The following assumptions are made:
#   1) BLS keys are in the path set by local var in the `launch_validator` function of launch-node.sh
#   2) BLS passphrase for all keys are the same & passphrases are taken as a plain text by the file
#        at a path set by local var in the `launch_validator` function of launch-node.sh
#   3) Files controlled by the daemon are in the home directory for the user of the harmony node daemon.
#   4) This install script is ran as the user for the harmony node daemon.
#
# Usage:
#    bash <(curl -s https://raw.githubusercontent.com/harmony-one/experiment-deploy/master/tools/install-node.sh) <parameter>
#
# Example:
#    bash <(curl -s https://raw.githubusercontent.com/harmony-one/experiment-deploy/master/tools/install-node.sh) -N mainnet -n validator
#    bash <(curl -s https://raw.githubusercontent.com/harmony-one/experiment-deploy/master/tools/install-node.sh) -N mainnet -n validator -a
#    bash <(curl -s https://raw.githubusercontent.com/harmony-one/experiment-deploy/master/tools/install-node.sh) -N mainnet -n explorer -s 1

set -e

function install_daemon(){
  local launch_script_source="https://raw.githubusercontent.com/harmony-one/experiment-deploy/master/tools/launch-node.sh"
  local launch_script_path="$HOME/launch-node.sh"
  local service_file_path="/lib/systemd/system/harmony.service"
  local env_file_path="$HOME/launchargs"
  local service_file="[Unit]
Description=harmony service
After=network.target

[Service]
Type=simple
Restart=on-failure
RestartSec=1
StartLimitInterval=0
StartLimitBurst=0
User=$USER
WorkingDirectory=$HOME
EnvironmentFile=$env_file_path
StandardError=syslog
SyslogIdentifier=harmony
ExecStart=$launch_script_path -N \$NETWORK -n \$NODE_TYPE -s \$SHARD -a \$ARCHIVAL
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
"
  local launchargs="NETWORK=$1
NODE_TYPE=$2
SHARD=$3
ARCHIVAL=$4
"
  echo "$launchargs" > "$env_file_path"
  curl -o "$launch_script_path" "$launch_script_source" -L
  chmod +x "$launch_script_path"
  sudo echo "$service_file" | sudo tee "$service_file_path" > /dev/null
  sudo chmod 644 "$service_file_path"
  sudo systemctl enable harmony
  sudo systemctl daemon-reload
}

function install_node_sh(){
  local node_sh_source="https://raw.githubusercontent.com/harmony-one/harmony/main/scripts/node.sh"
  local node_sh_path="$HOME/node.sh"
  if [ ! -f "$node_sh_path" ]; then
    echo "node.sh not found at $node_sh_path , downloading it from $node_sh_source ..."
    curl -o "$node_sh_path" "$node_sh_source" -L
  fi
  chmod +x "$node_sh_path"
  sudo "$node_sh_path" -s
}


# Script Main
if (( "$EUID" == 0 )); then
  echo "do not install as root, exiting..."
  exit 1
fi

unset node_type node_shard network archival OPTIND OPTARG opt
network=mainnet
node_type=validator
node_shard=-1
archival=false
while getopts N:n:s:a opt; do
  case "${opt}" in
  N) network="${OPTARG}" ;;
  n) node_type="${OPTARG}" ;;
  s) node_shard="${OPTARG}" ;;
  a) archival=true ;;
  *)
    echo "
     Internal node install script help message

     Examples:
     install-node.sh -N mainnet -n validator
     install-node.sh -N mainnet -n explorer -s 2

     Option:         Help:
     -N <network>    specify node network (options are from node.sh; default: mainnet)
     -n <type>       specify node type (options are from node.sh; default: validator)
     -s <shard>      specify node shard (only required for explorer node type)
     -a              toggle node is archival (explorer is always archival)"
    exit
    ;;
  esac
done
shift $((${OPTIND} - 1))

if [ $# -ne 0 ]; then
  echo "arguments provided, script only takes options. Exiting..."
  exit 2
fi

if pgrep harmony; then
  echo "harmony process is running, stop process before installing..."
  exit 3
fi

install_node_sh
install_daemon "$network" "$node_type" "$node_shard" "$archival"
