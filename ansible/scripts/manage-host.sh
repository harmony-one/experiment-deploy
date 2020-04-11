# ansible-playbook -i inventory/hmy.hosts -e 'inventory=watchdog user=lc' playbooks/hmyhost.yml
# ansible-playbook -i inventory/hmy.hosts -e 'inventory=jenkins user=lc' playbooks/hmyhost.yml
ansible-playbook -i inventory/hmy.hosts -e 'inventory=devop user=lc' playbooks/hmyhost.yml
