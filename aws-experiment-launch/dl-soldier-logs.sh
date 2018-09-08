#!/bin/bash

# set -x

GREP='grep -E'
DIR=$(pwd)
DC=distribution_config.txt
CFG=configuration.txt
SCP=scp
UNAME=ec2-user

function usage
{
   ME=$(basename $0)

   cat<<EOT
Usage: $ME [OPTIONS] NODES

OPTIONS:
   -h             print this help
   -s session     set the session id (mandatory)
   -u user        set the user name to login to nodes (default: $UNAME)

NODES:
   leader         download leader logs only
   validator      download validator logs only
   all            download all logs
EOT
   exit 1
}

function download_logs
{
   local node=$1
   mkdir -p logs/$SESSION/$node

   IP=( $(${GREP} $node ${DC} | cut -f 1 -d ' ') )
   REGION=( $(${GREP} $node ${DC} | cut -f 5 -d ' ' | cut -f 1 -d '-') )

   i=0
   for r in "${REGION[@]}"; do
      # found azure node
      if [ "$r" == "node" ]; then
         ${SCP} -r ${UNAME}@${IP[$i]}:/home/tmp_log logs/${SESSION}/$node
      else
         key=$(${GREP} ^$r ${CFG} | cut -f 3 -d ,)
         ${SCP} -i $DIR/../keys/$key.pem -r ${UNAME}@${IP[$i]}:/home/tmp_log logs/${SESSION}/$node
      fi
      (( i++ ))
   done
}

########################################

while getopts "hs:" option; do
   case $option in
      s) SESSION=$OPTARG ;;
      h|?) usage ;;
   esac
done

shift $(($OPTIND-1))

if [ -z "$SESSION" ]; then
   usage
fi

NODE=$@

case $NODE in
   leader) download_logs leader ;;
   validator) download_logs validator ;;
   all) download_logs leader && download_logs validator ;;
   *) usage ;;
esac
