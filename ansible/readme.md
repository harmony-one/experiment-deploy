# introduction
Ansible is the new tool we used for network operations.
All the host info used by ansible is in `/etc/ansible/hosts`
Please make sure you have the ssh agent running with the right mainnet keys before any ansible operation.
```bash
ssh-add -l
2048 SHA256:K9D3flNNlwei50Hz78PXubKNacmSQqxiTaQfHf92bP8 leochen@MBP15.local (RSA)
```

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
# mainnet upgrade operation

```bash
cd ~/experiment-deploy/ansible
./scripts/upgrade-mainnet.sh

1) rolling_upgrade
2) restart
3) force_upgrade
4) quit
```
All the actions can operation on either a shard, a group, or a single host.
By default, the `rolling_upgrade` action won't upgrade the current leader node.
You need to use `force_upgrade` action to upgrade leader.
`restart` can restart a node, or a shard, ex, s0, s1, s2, s3.

