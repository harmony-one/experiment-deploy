ansible-playbook playbooks/cleanup.yml -i inventory/ostn.ankr.yml -e 'user=root inventory=sentry'
ansible-playbook playbooks/cleanup.yml -i inventory/ostn.ankr.yml -e 'user=root inventory=leo130'
ansible-playbook playbooks/cleanup.yml -i inventory/ostn.ankr.yml -e 'user=root inventory=ostnexp'
