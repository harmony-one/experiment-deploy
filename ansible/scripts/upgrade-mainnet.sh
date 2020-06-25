#!/bin/bash

PS3="Press 4 to quit: "

select opt in rolling_upgrade restart force_upgrade quit; do
   case $opt in
      rolling_upgrade)
         read -p "The group (s{0..3}/s{0..3}_canary/canary): " shard
         read -p "The release bucket: " release
         ANSIBLE_STRATEGY=free ansible-playbook playbooks/upgrade-node.yml -f 2 -e "inventory=${shard} stride=2 upgrade=${release}"
         echo "NOTED: the leader won't be upgraded. Please upgrade leader with force_update=true"
         ;;
      restart)
         read -p "The node group or node IP: " shard
         read -p "Number of nodes in one batch (1-50): " batch
         read -p "Skip checking of consensus (true/false): " skip
         ANSIBLE_STRATEGY=free ansible-playbook playbooks/restart-node.yml -f $batch -e "inventory=${shard} stride=${batch} skip_consensus_check=${skip}"
         ;;
      force_upgrade)
         read -p "The group (s{0..3}/s{0..3}_canary/canary): " shard
         read -p "The release bucket: " release
         # force upgrade and no consensus check
         ANSIBLE_STRATEGY=free ansible-playbook playbooks/upgrade-node.yml -f 50 -e "inventory=${shard} stride=50 upgrade=${release} force_update=true skip_consensus_check=true"
         ;;
      quit)
         break
         ;;
      *)
         echo "Invalid option: $REPLY"
         ;;
   esac
done
