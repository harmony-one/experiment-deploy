ansible-playbook -i inventory/ostn.ankr.yml -e 'inventory=sentry user=root' --vault-id leo playbooks/install-node.yml
