#!/usr/bin/env bash

# NOTE: This script is meant to be consumed by the harmony daemon

set -e

node_file_dir="$HOME"
node_sh_path="$node_file_dir/node.sh"

function check_node_type() {
  case $1 in
  validator)
    echo "node type is validator"
    ;;
  explorer)
    if [ -z "$2" ]; then
      echo "explorer shard not provided, exiting..."
      exit 2
    fi
    echo "node type is explorer for shard $2"
    ;;
  *)
    echo "unknown node type, exiting..."
    exit 1
    ;;
  esac
}

function check_node_sh() {
  local node_sh_source=https://harmony.one/node.sh
  if [ ! -f "$node_sh_path" ]; then
    echo "node.sh not found at $node_sh_path . Downloading..."
    curl -oL "$node_sh_path" $node_sh_source
  fi
  chmod +x "$node_sh_path"
}

function launch_validator() {
  local network=$1
  local bls_pass=$HOME/bls.pass
  local bls_keys_dir="$HOME/.hmy/blskeys"
  if [ ! -d "$bls_keys_dir" ]; then
    echo "bls keys directory not  found at $bls_keys_dir , exiting..."
    exit 3
  fi
  if ! find "$bls_keys_dir" -type f -name '*.key'; then
    echo "no file key ending with .key found in $bls_keys_dir , exiting..."
    exit 4
  fi
  if [ ! -f "$bls_pass" ]; then
    echo "bls passphrase file not found at $bls_pass , exiting..."
    exit 5
  fi
  $node_sh_path -1 -N "$network" -S -P -p "$bls_pass" -M -D -f "$bls_keys_dir"
}

function launch_explorer() {
  local network=$1
  local shard=$2
  local bls_key="$node_file_dir/bls.key"   # Dummy keys
  local bls_pass="$node_file_dir/bls.pass" # Dummy keys
  echo >"$bls_key"
  echo >"$bls_pass"
  $node_sh_path -1 -N "$network" -S -P -D -T explorer -i "$shard" -k "$bls_key" -p "$bls_pass" -A
}

# Script Main
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
     Internal node launch script help message

     Examples:
     launch-node.sh -N mainnet -n validator
     launch-node.sh -N mainnet -n explorer -s 2

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
  exit 6
fi

check_node_type "$node_type" "$node_shard"
check_node_sh
if [ "$node_type" == "validator" ]; then
  launch_validator "$network"
else
  launch_explorer "$network" "$node_shard"
fi
