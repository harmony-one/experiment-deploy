#!/usr/bin/env bash

# set -x

GREP='grep -E'
DIR=$(pwd)
DC=distribution_config.txt
CFG=configuration.txt
SCP='scp -o StrictHostKeyChecking=no'
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
   -p parallel    parallelize num of jobs (default: $PARALLEL)

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

   end=0
   group=0

   count=0
   TOTAL=${#IP[@]}
   execution=1

   SECONDS=0
   while [ $execution -eq 1 ]; do
      start=$(( $PARALLEL * $group ))
      end=$(( $PARALLEL + $start - 1 ))

      if [ $end -ge $(( $TOTAL - 1 )) ]; then
         end=$(( $TOTAL - 1 ))
         execution=0
      fi

      echo processing group: $group \($start to $end\)

      for i in $(seq $start $end); do
         r=${REGION[$i]}
         if [ "$r" == "node" ]; then
            ${SCP} -r ${UNAME}@${IP[$i]}:/home/tmp_log logs/${SESSION}/$node 2> /dev/null &
         else
            key=$(${GREP} ^$r ${CFG} | cut -f 3 -d ,)
            ${SCP} -i $DIR/../keys/$key.pem -r ${UNAME}@${IP[$i]}:/home/tmp_log logs/${SESSION}/$node 2> /dev/null &
         fi
         (( count++ ))
      done
      wait

      (( group++ ))
   done
   duration=$SECONDS

   echo downloaded $count logs used $(( $duration / 60 )) minutes $(( $duration % 60 )) seconds
}

########################################

PARALLEL=100

while getopts "hs:p:" option; do
   case $option in
      s) SESSION=$OPTARG ;;
      p) PARALLEL=$OPTARG ;;
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
