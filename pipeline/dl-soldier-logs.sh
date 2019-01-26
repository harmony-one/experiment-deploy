#!/usr/bin/env bash

# set -x

GREP='grep -E'
DIR=$(pwd)
DC=distribution_config.txt
CFG=configuration.txt
SCP='scp -o StrictHostKeyChecking=no -o LogLevel=error'
SSH='ssh -o StrictHostKeyChecking=no -o LogLevel=error'
UNAME=ec2-user

function usage
{
   ME=$(basename $0)

   cat<<EOT
Usage: $ME [OPTIONS] ACTIONS

OPTIONS:
   -h             print this help
   -s session     set the session id (mandatory)
   -u user        set the user name to login to nodes (default: $UNAME)
   -p parallel    parallelize num of jobs (default: $PARALLEL)
   -g group       set group name (leader, validator, client, all)
   -D filename    specify the distribution configuration file (default: $DC)

NODES:
   benchmark      download benchmark logs
   soldier        download soldier logs
   version        execute 'benchmark -version' command
EOT
   exit 1
}

function download_logs
{
   local type=$1
   local node=$2
   mkdir -p logs/$SESSION/$node

   IP=( $(${GREP} $node ${DC} | cut -f 1 -d ' ') )
   REGION=( $(${GREP} $node ${DC} | cut -f 5 -d ' ' | cut -f 1 -d '-') )

   end=0
   group=0

   count=0
   TOTAL=${#IP[@]}
   execution=1

   case $type in
      benchmark)
         FILE=/home/tmp_log
         ;;
      soldier)
         FILE=soldier*.log
         ;;
   esac

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
            ${SCP} -r ${UNAME}@${IP[$i]}:${FILE} logs/${SESSION}/$node 2> /dev/null &
         else
            key=$(${GREP} ^$r ${CFG} | cut -f 3 -d ,)
            ${SCP} -i $DIR/../keys/$key.pem -r ${UNAME}@${IP[$i]}:${FILE} logs/${SESSION}/$node 2> /dev/null &
         fi
         (( count++ ))
      done
      wait

      (( group++ ))
   done
   duration=$SECONDS

   echo downloaded $count logs used $(( $duration / 60 )) minutes $(( $duration % 60 )) seconds
}

function run_cmd
{
   local cmd=$1
   local node=$2

   logdir=logs/$SESSION/$cmd

   mkdir -p $logdir

   IP=( $(${GREP} $node ${DC} | cut -f 1 -d ' ') )
   REGION=( $(${GREP} $node ${DC} | cut -f 5 -d ' ' | cut -f 1 -d '-') )

   end=0
   group=0

   count=0
   TOTAL=${#IP[@]}
   execution=1

   case $cmd in
      version)
         CMD='LD_LIBRARY_PATH=. /home/ec2-user/harmony -version'
         ;;
   esac

   SECONDS=0
   while [ $execution -eq 1 ]; do
      start=$(( $PARALLEL * $group ))
      end=$(( $PARALLEL + $start - 1 ))

      if [ $end -ge $(( $TOTAL - 1 )) ]; then
         end=$(( $TOTAL - 1 ))
         execution=0
      fi

      echo run cmd: $CMD on group: $group \($start to $end\)

      for i in $(seq $start $end); do
         r=${REGION[$i]}
         if [ "$r" == "node" ]; then
            ${SSH} ${UNAME}@${IP[$i]} "$CMD" 2>&1 | tee $logdir/${IP[$i]}.log &
         else
            key=$(${GREP} ^$r ${CFG} | cut -f 3 -d ,)
            ${SSH} -i $DIR/../keys/$key.pem ${UNAME}@${IP[$i]} "$CMD" 2>&1 | tee $logdir/${IP[$i]}.log &
         fi
         (( count++ ))
      done
      wait

      (( group++ ))
   done
   duration=$SECONDS

   echo run cmd $CMD $count times used $(( $duration / 60 )) minutes $(( $duration % 60 )) seconds

}

########################################

PARALLEL=100

while getopts "hs:p:g:D:" option; do
   case $option in
      s) SESSION=$OPTARG ;;
      p) PARALLEL=$OPTARG ;;
      g) NODE=$OPTARG ;;
      D) DC=$OPTARG ;;
      h|?) usage ;;
   esac
done

shift $(($OPTIND-1))

if [ -z "$SESSION" ]; then
   usage
fi

ACTION=$@

case $ACTION in
   benchmark|soldier)
      if [ "$NODE" == "all" ]; then
         download_logs $ACTION leader
         download_logs $ACTION validator
         download_logs $ACTION client
      else
         download_logs $ACTION $NODE
      fi
      ;;
   version)
      run_cmd $ACTION $NODE
      ;;
   *) usage ;;
esac
