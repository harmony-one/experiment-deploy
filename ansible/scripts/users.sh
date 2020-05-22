ansible-playbook playbooks/users.yml -e 'inventory=tdevop' -i inventory/hmy.hosts
ansible-playbook playbooks/users.yml -e 'inventory=watchdog' -i inventory/hmy.hosts
ansible-playbook playbooks/users.yml -e 'inventory=jenkins' -i inventory/hmy.hosts
ansible-playbook playbooks/users.yml -e 'inventory=devop' -i inventory/hmy.hosts
