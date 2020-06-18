#!/bin/bash

PS3="Select the operation: "

select opt in rolling_upgrade force_upgrade quit; do
   case $opt in
      rolling_upgrade)
         read -p "The group (s{0..3}/s{0..3}_canary/canary): " shard
         read -p "The release bucket: " release
         ansible-playbook playbooks/upgrade-node.yml -e "inventory=${shard} stride=1 upgrade=${release}"
         echo "NOTED: the leader won't be upgraded. Please upgrade leader with force_update=true"
         ;;
      force_upgrade)
         read -p "The group (s{0..3}/s{0..3}_canary/canary): " shard
         read -p "The release bucket: " release
         # force upgrade and no consensus check
         ANSIBLE_STRATEGY=free ansible-playbook playbooks/upgrade-node.yml -f 10 -e "inventory=${shard} stride=10 upgrade=${release} force_update=true skip_consensus_check=true"
         ;;
      quit)
         break
         ;;
      *)
         echo "Invalid option: $REPLY"
         ;;
   esac
done
