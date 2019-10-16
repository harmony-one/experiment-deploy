#!/bin/bash

# this script upload validator logs to a s3 bucket
# it shall support both legacy and terraform nodes

# https://www.linuxjournal.com/content/validating-ip-address-bash-script
function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

function myip() {
# get ipv4 address only, right now only support ipv4 addresses
   PUB_IP=$(dig -4 @resolver1.opendns.com ANY myip.opendns.com +short)
   if valid_ip $PUB_IP; then
      echo "public IP address autodetected: $PUB_IP"
   else
      echo "NO valid public IP found: $PUB_IP"
      exit 1
   fi
}

## main ##
myip

NETWORK=${1:-mainnet}

if [ -d $HOME/latest ]; then
   LOGDIR=$HOME/latest
elif [ -d $HOME/../tmp_log/log-20190628.153354 ]; then
   LOGDIR=$HOME/../tmp_log/log-20190628.153354
fi

aws --profile uploadlog s3 sync $LOGDIR s3://harmony-benchmark/logs/$NETWORK/${PUB_IP}/

sudo rm -f $LOGDIR/*.gz
