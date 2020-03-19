# install ansible
https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html

# install ansible roles
```bash
ansible-galaxy install charliemaiors.rclone_ansible
ansible-galaxy install ryandaniels.create_users

```
# role: create_users
https://github.com/ryandaniels/ansible-role-create-users

# what is ansible vault
https://docs.ansible.com/ansible/latest/user_guide/vault.html

# create users on users / test

* edit inventory/test.hosts file to use your own host IP
* make sure you have proper ssh setup to login to your own host

## on ankr host
```bash
cd ~/experiment-deploy/ansible
ansible-inventory --list -i inventory/test.hosts
ansible-playbook playbooks/create-users.yml --ask-vault-pass --extra-vars "inventory=h2 user=ec2-user" -i inventory/test.hosts
```

## on aws instance
```bash
cd ~/experiment-deploy/ansible
ansible-inventory --list -i inventory/hmy.hosts
ansible-playbook playbooks/users.yml --ask-vault-pass --extra-vars "inventory=devop" -i inventory/hmy.hosts
```


