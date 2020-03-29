#ansible-playbook -i inventory/ostn.ankr.yml -e 'inventory=leo130 user=root' --vault-password-file .vaultpass-lc playbooks/install-node.yml
ansible-playbook -i inventory/ostn.ankr.yml -e 'inventory=ostnexp user=root' --vault-password-file .vaultpass-lc playbooks/install-node.yml
#ansible-playbook -i inventory/ostn.ankr.yml -e 'inventory=sentry user=root' --vault-password-file .vaultpass-lc playbooks/install-node.yml
