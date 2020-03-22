ansible-playbook -i inventory/ostn.ankr.yml playbooks/cleanup.yml -e 'inventory=ostnexp user=root'
ansible-playbook -i inventory/ostn.ankr.yml playbooks/install-node.yml -e 'inventory=ostnexp user=root'
