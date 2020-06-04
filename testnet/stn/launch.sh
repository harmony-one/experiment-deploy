#!/bin/bash

SHARD=2
SLOT=10
KEY=1
NETWORK=testnet

HOSTFILE=$(pwd)/stn.json
KEYPATH=~/tmp/blskeys-tn

DEPLOYDIR=~/go/src/github.com/harmony-one/experiment-deploy

ansible --list-hosts p2p | tail -n +2 | tr -d " " | jq -R -s -c 'split("\n")[:-1]' > $HOSTFILE

$DEPLOYDIR/bin/genbls \
-host $HOSTFILE \
-network $NETWORK \
-shard $SHARD \
-slot $SLOT \
-key $KEY \
-pass ~/tmp/bls.nopass \
-keypath $KEYPATH

rsync -av files $DEPLOYDIR/ansible/playbooks/roles/node

for (( s=0; s<$SHARD; s++ )); do
   python3 $DEPLOYDIR/pipeline/r53update.py stn $s $(ansible --list-hosts p2ps${s} | tail -n +2 | tr -d " " | tr "\n" " ")
done

pushd ~/go/src/github.com/harmony-one/harmony
export WHOAMI=stressnet
./scripts/go_executable_build.sh
./scripts/go_executable_build.sh release
popd

pushd $DEPLOYDIR/ansible

# setup sysctl
ansible-playbook playbooks/sysctl-setup.yml -e 'inventory=p2p user=hmy'

# install node_exporter
ansible-playbook playbooks/install-node-exporter.yml -e 'inventory=p2p user=hmy'

# install harmony node
ansible-playbook playbooks/install-node.yml -e 'inventory=p2p network=stn user=hmy' --vault-password-file ${DEPLOYDIR}/ansible/.vaultpass-lc

# install explorer node
ansible-playbook playbooks/install-node.yml -e 'inventory=p2pexp user=ec2-user network=stressnet'

# do upgrade
# ansible-playbook playbooks/upgrade-node.yml -e 'inventory=p2p upgrade=stressnet user=hmy'

popd
