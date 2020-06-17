#!/bin/bash

PS3="Select the operation: "

select opt in rolling_upgrade force_upgrade quit; do
   case $opt in
      rolling_upgrade)
         # regualr rolling upgrade, one node at a time
         ansible-playbook playbooks/upgrade-node.yml -e 'inventory=p2p stride=1 upgrade=canary user=hmy'
         ;;
      force_upgrade)
         # force upgrade and no consensus check
         ANSIBLE_STRATEGY=free ansible-playbook playbooks/upgrade-node.yml -f 10 -e 'inventory=p2p stride=10 upgrade=canary user=hmy force_update=true skip_consensus_check=true'
         ;;
      quit)
         break
         ;;
      *)
         echo "Invalid option: $REPLY"
         ;;
   esac
done
