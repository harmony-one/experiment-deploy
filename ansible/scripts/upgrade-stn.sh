#!/bin/bash

PS3="Select 4 to quit: "

while true; do
   select opt in rolling_upgrade restart_shard_or_node force_upgrade quit; do
      case $opt in
         rolling_upgrade)
            read -p "The group (p2ps{0..1}/p2p): " shard
            read -p "The release bucket: " release
            ANSIBLE_STRATEGY=free ansible-playbook playbooks/upgrade-node.yml -e "inventory=${shard} stride=1 upgrade=${release}"
            echo "NOTED: the leader won't be upgraded. Please upgrade leader with force_update=true"
            ;;
         restart_shard_or_node)
            read -p "The node group or node IP: " shard
            ANSIBLE_STRATEGY=free ansible-playbook playbooks/restart-node.yml -f 30 -e "inventory=${shard} stride=30"
            ;;
         force_upgrade)
            read -p "The group (p2ps{0..1}/p2p): " shard
            read -p "The release bucket: " release
            # force upgrade and no consensus check
            ANSIBLE_STRATEGY=free ansible-playbook playbooks/upgrade-node.yml -f 20 -e "inventory=${shard} stride=20 upgrade=${release} force_update=true skip_consensus_check=true"
            ;;
         quit)
            exit
            ;;
         *)
            echo "Invalid option: $REPLY"
            ;;
      esac
   done
done
