#!/usr/bin/env bash

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
Restart=always
RestartSec=1
StartLimitInterval=0
StartLimitBurst=0
User=$USER
WorkingDirectory=$HOME
EnvironmentFile=$env_file_path
ExecStart=$launch_script_path -N \$NETWORK -n \$NODE_TYPE -s \$SHARD

[Install]
WantedBy=multi-user.target
"
  local launchargs="NETWORK=$1
NODE_TYPE=$2
SHARD=$3
"
  echo "$launchargs" > "$env_file_path"
  curl -oL "$launch_script_path" "$launch_script_source"
  chmod +x "$launch_script_path"
  sudo echo "$service_file" | sudo tee "$service_file_path" > /dev/null
  sudo chmod 644 "$service_file_path"
  sudo systemctl enable harmony
  sudo systemctl daemon-reload
}

function install_node_sh(){
  local node_sh_source="https://harmony.one/node.sh"
  local node_sh_path="$HOME/node.sh"
  if [ ! -f "$node_sh_path" ]; then
    echo "node.sh not found at $node_sh_path , downloading it from $node_sh_source ..."
    curl -oL "$node_sh_path" "$node_sh_source"
  fi
  chmod +x "$node_sh_path"
  sudo "$node_sh_path" -s
}


# Script Main
if (( "$EUID" == 0 )); then
  echo "do not install as root, exiting..."
  exit 1
fi

unset node_type node_shard network OPTIND OPTARG opt
network=mainnet
node_type=validator
node_shard=
while getopts N:n:s: opt; do
  case "${opt}" in
  N) network="${OPTARG}" ;;
  n) node_type="${OPTARG}" ;;
  s) node_shard="${OPTARG}" ;;
  *)
    echo "
     Internal node install script help message

     Examples:
     install-node.sh -N mainnet -n validator
     install-node.sh -N mainnet -n explorer -s 2

     Option:         Help:
     -N <network>    specify node network (mainnet, testnet, staking, partner, stress, devnet, tnet; default: mainnet)
     -n <type>       specify node type (validator, explorer; default: validator)
     -s <shard>      specify node shard (only required for explorer node type)"
    exit
    ;;
  esac
done
shift $((${OPTIND} - 1))

if [ $# -ne 0 ]; then
  echo "arguments provided, script only takes options. Exiting..."
  exit 2
fi

install_node_sh
install_daemon "$network" "$node_type" "$node_shard"
