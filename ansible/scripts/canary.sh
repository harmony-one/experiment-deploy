ansible-playbook -i inventory/mainnet.hosts -e 'inventory=canary upgrade=upgrade' playbooks/upgrade-node.yml
