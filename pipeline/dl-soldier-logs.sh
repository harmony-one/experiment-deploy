#!/usr/bin/env bash

# set -x
unset -v progname progdir
progname="${0##*/}"
case "${0}" in
*/*) progdir="${0%/*}";;
*) progdir=".";;
esac

. "${progdir}/util.sh"

source ./common.sh || exit 1

GREP='grep -E'
DIR=$(pwd)
CFG=configuration.txt
SCP='scp -o StrictHostKeyChecking=no -o LogLevel=error -o ConnectTimeout=5 -o GlobalKnownHostsFile=/dev/null'
SSH='ssh -o StrictHostKeyChecking=no -o LogLevel=error -o ConnectTimeout=5 -o GlobalKnownHostsFile=/dev/null'
UNAME=ec2-user
KEYDIR=${HSSH_KEY_DIR:-~/.ssh/keys}

function usage
{
   ME=$(basename $0)

   cat<<EOT
Usage: $ME [OPTIONS] ACTIONS

OPTIONS:
   -h             print this help
   -p profile     specify the benchmark profile in $CONFIG_DIR directory (default: $PROFILE)
                  supported profiles (${PROFILES[@]})
   -u user        set the user name to login to nodes (default: $UNAME)
   -P parallel    parallelize num of jobs (default: $PARALLEL)
   -g group       set group name (leader, validator, client, all)
   -D filename    specify the distribution configuration file (default: $DC)
   -R retention   retention days of logs (default: $DAYS)

ACTIONS:
   benchmark         download benchmark logs
   benchmark-legacy  download benchmark logs from legacy nodes
   soldier           download soldier logs
   version           execute 'benchmark -version' command
   db                download local leveldb
EOT
   exit 1
}

function download_logs
{
   local type=$1
   local node=$2

   for shard in $(seq 0 $(( ${configs[benchmark.shards]} - 1 ))); do
      logging download log in shard: $shard
      mkdir -p logs/$SESSION/$node/shard${shard}

      readarray -t IP < logs/$SESSION/shard${shard}.txt

      end=0
      group=0

      count=0
      TOTAL=${#IP[@]}
      execution=1

      case $type in
         benchmark) FILE=~/latest ;;
         benchmark-legacy) FILE=/home/tmp_log ;;
         soldier) FILE=soldier*.log ;;
         db) FILE=db*.tgz ;;
      esac

      while [ $execution -eq 1 ]; do
         start=$(( $PARALLEL * $group ))
         end=$(( $PARALLEL + $start - 1 ))

         if [ $end -ge $(( $TOTAL - 1 )) ]; then
            end=$(( $TOTAL - 1 ))
            execution=0
         fi

         echo processing group: $group \($start to $end\)

         for i in $(seq $start $end); do
            key=$(find_key_from_ip ${IP[$i]})
            rsync -a -e "${SSH} -i $KEYDIR/$key" ${UNAME}@${IP[$i]}:${FILE} logs/${SESSION}/$node/shard${shard} 2> /dev/null &
            (( count++ ))
         done
         wait

         (( group++ ))
      done
      expense downloadlog
   done
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
      db)
         CMD='tar cfz db-IP.tgz harmony_db_*'
         NCMD=$CMD
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
         key=$(find_key_from_ip ${IP[$i]})
         if [ "$r" == "node" ]; then
            ${SSH} -i $KEYDIR/$key ${UNAME}@${IP[$i]} "$CMD" 2>&1 | tee $logdir/${IP[$i]}.log &
         else
            # key=$(${GREP} ^$r ${CFG} | cut -f 3 -d ,)
            if [ "$cmd" == "db" ]; then
               CMD=$(echo $NCMD | sed "s/IP/${IP[$i]}/")
            fi
            ${SSH} -i $KEYDIR/$key ${UNAME}@${IP[$i]} "$CMD" 2>&1 | tee $logdir/${IP[$i]}.log &
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
PROFILE=tiny
PROFILES=( $(ls $CONFIG_DIR/benchmark-*.json | sed -e "s,$CONFIG_DIR/benchmark-,,g" -e 's/.json//g') )
SESSION_FILE=$CONFIG_DIR/profile-${PROFILE}.json
BENCHMARK_FILE=$CONFIG_DIR/benchmark-${PROFILE}.json
NODE=leader

while getopts "hs:p:P:g:D:" option; do
   case $option in
      p)
         PROFILE=$OPTARG
         SESSION_FILE=$CONFIG_DIR/profile-${PROFILE}.json
         BENCHMARK_FILE=$CONFIG_DIR/benchmark-${PROFILE}.json
         [ ! -e $BENCHMARK_FILE ] && errexit "can't find benchmark config file : $BENCHMARK_FILE"
         ;;
      P) PARALLEL=$OPTARG ;;
      g) NODE=$OPTARG ;;
      D) DC=$OPTARG ;;
      h|?) usage ;;
   esac
done

shift $(($OPTIND-1))

read_profile $BENCHMARK_FILE

[ ! -e $SESSION_FILE ] && errexit "can't find profile config file : $SESSION_FILE"
SESSION=$(cat $SESSION_FILE | $JQ .sessionID)
DC=logs/$SESSION/distribution_config.txt

ACTION=$@

case $ACTION in
   benchmark|benchmark-legacy|soldier)
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
   db)
      run_cmd $ACTION $NODE
      download_logs $ACTION $NODE
      ;;
   *) usage ;;
esac
