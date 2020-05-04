#!/usr/bin/env bash

# This script is used to enable systemd service on legacy nodes.
# It is a one-time operation to convert legacy nodes to use systemd service.
#
# [RELEASE]
# aws s3 cp enable-systemd-service.sh s3://haochen-harmony-pub/pub/systemd/install.sh --acl public-read
# aws s3 cp harmony.service.template s3://haochen-harmony-pub/pub/systemd/harmony.service.template --acl public-read
#
# [MAINNET/LRTN]
# https://harmony.one/node.sh
# s3://haochen-harmony-pub/pub/systemd/mainnet/validator/harmony.service
# s3://haochen-harmony-pub/pub/systemd/mainnet/explorer/harmony.service
#
# [OSTN/STN]
# https://harmony.one/master/node.sh
# s3://haochen-harmony-pub/pub/systemd/master/validator/harmony.service
# s3://haochen-harmony-pub/pub/systemd/master/explorer/harmony.service
#
# [USAGE]
# curl -s -S -L https://haochen-harmony-pub.s3.amazonaws.com/pub/systemd/install.sh | bash -s <parameter>
#
# [EXAMPLES]
# curl -s -S -L https://haochen-harmony-pub.s3.amazonaws.com/pub/systemd/install.sh | bash -s stn
# curl -s -S -L https://haochen-harmony-pub.s3.amazonaws.com/pub/systemd/install.sh | bash -s ostn
# curl -s -S -L https://haochen-harmony-pub.s3.amazonaws.com/pub/systemd/install.sh | bash -s ostn explorer 1
#
# TODO: auto detect network/nodetype/shard, but since this is a one-time cost, we probably shouldn't invest too much in it
# TODO: for testnet node, when we launch new testnet, we shall use systemd service from beginning

function usage()
{
   ME=$(basename "$0")
   cat<<-EOU

Usage: $ME network_type node_type [shard_id]

   network_type:     mandatory: ostn, lrtn, stn, pstn, mainnet (default: ostn)
   node_type:        mandatory: explorer, validator (default: validator)
   shard_id:         optional: needed if node_type is explorer

EOU
   exit 0
}

case "$1" in
   "-h"|"-H"|"-?"|"--help")
      usage;;
esac

NETWORK=${1:-ostn}
TYPE=${2:-validator}
SHARD=${3}

SERVICE=https://haochen-harmony-pub.s3.amazonaws.com/pub/systemd/harmony.service.template
BLSPASS=blsnopass.txt

case $NETWORK in
   ostn)
      NODESH=master/node.sh
      NET=staking
      EXTRA+='-z'
      ;;
   stn)
      NODESH=master/node.sh
      NET=stress
      EXTRA+='-z'
      ;;
   pstn)
      NODESH=node.sh
      NET=partner
      EXTRA+='-z'
      ;;
   lrtn)
      NODESH=node.sh
      NET=testnet
      ;;
   mainnet)
      NODESH=node.sh
      NET=main
      BLSPASS=blspass.txt
      ;;
   *) echo "unknown network type, exiting ..."
      exit 1
esac

case $TYPE in
   validator)
      echo "node type is: $TYPE"
      EXTRA=
      ;;
   explorer)
      echo "node type is: $TYPE"
      if [ -z "${SHARD}" ]; then
         echo must specify SHARD if node type is explorer
         exit 1
      fi
      EXTRA="-i ${SHARD} "
      ;;
   *)
      echo "unknown node type, exiting ..."
      exit 1
esac

if systemctl list-unit-files harmony.service | grep -q enabled; then
   echo harmony service is already enabled in systemd, exiting ...
   exit 0
fi

curl -LO https://harmony.one/${NODESH}
chmod +x node.sh

curl -LO ${SERVICE}
USER=$(whoami)
HOME=${HOME}

cp -f $BLSPASS bls.pass

sed "s,%%USER%%,$USER,g;s,%%HOME%%,$HOME,g;s,%%NETWORK%%,$NET,;s,%%NODETYPE%%,$TYPE,;s,%%BLSPASS%%,bls.pass,;s,%%EXTRA%%,$EXTRA," harmony.service.template > harmony.service
sudo cp -f harmony.service /lib/systemd/system/harmony.service

# remove legacy harmony.service
sudo rm -f /etc/systemd/system/harmony.service

if pgrep harmony; then
   echo harmony node is still running, stop it
   if ! sudo pkill harmony; then
      echo can not kill harmony process, exiting ..
      exit 2
   fi
fi

# remove tmp_log
sudo rm -rf /home/tmp_log
# remove latest symlink
sudo rm -f latest
sudo chown -R "${USER}"."${USER}" ./* ./.*

mkdir -p .hmy/blskeys
# create a dummy key for explorer which requires no blskey to run
if [ "$TYPE" = "explorer" ]; then
   touch .hmy/blskeys/dummy.bls.key
else
   for i in *.key; do
      n=${i%.key}
      mv -f $i .hmy/blskeys
      cp bls.pass .hmy/blskeys/${n}.pass
   done
fi

sudo systemctl daemon-reload
sudo systemctl enable harmony
sudo systemctl start harmony

sleep 3s

pgrep harmony | tee harmony.pid
