ansible-playbook -e 'inventory=test1 user=ec2-user' -i inventory/ostn.hosts playbooks/update-systemd.yml
