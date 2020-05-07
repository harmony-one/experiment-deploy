#!/usr/bin/env bash

# set -x
unset -v progname progdir
progname="${0##*/}"
case "${0}" in
*/*) progdir="${0%/*}";;
*) progdir=".";;
esac

. "${progdir}/util.sh"
. "${progdir}/common.sh"

SCP='scp -o StrictHostKeyChecking=no -o LogLevel=error -o ConnectTimeout=5 -o GlobalKnownHostsFile=/dev/null'
SSH='ssh -o StrictHostKeyChecking=no -o LogLevel=error -o ConnectTimeout=5 -o GlobalKnownHostsFile=/dev/null'

function usage
{
   ME=$(basename $0)

   cat<<EOT
Usage: $ME [OPTIONS] ACTIONS

OPTIONS:
   -h             print this help
   -p profile     specify the benchmark profile in $CONFIG_DIR directory (default: $PROFILE)
                  supported profiles (${PROFILES[@]})
   -P parallel    parallelize num of jobs (default: $PARALLEL)

   -i ip          IP address of the node to be downloaded
   -s shard_id    download logs from all the nodes in the shard (default: $SHARD)

ACTIONS:
   log            download all logs and sync to s3 (default action)

   cleanup        cleanup latest/*.gz
   sync           sync logs to s3 bucket

EOT
   exit 1
}

function _download_logs_one_shard
{
   local shard=$1
   logging download log in shard: $shard
   local logdir
   logdir=logs/$PROFILE/logs/shard${shard}
   mkdir -p $logdir

   cat logs/$PROFILE/shard${shard}.txt | xargs -P ${PARALLEL} -I% bash -c "mkdir -p $logdir/%; ${SCP} %:latest/* $logdir/%/"
}

function sync_log
{
   local src=$1
   YEAR=$(date +"%y")
   MONTH=$(date +"%m")
   DAY=$(date +"%d")
   TIME=$(date +"%T")
   TSDIR="$PROFILE/$YEAR/$MONTH/$DAY/$TIME"
   S3URL=s3://harmony-benchmark/logs/$TSDIR
 
   if valid_ip $src; then
      local shard=$(grep -l $ip logs/${PROFILE}/shard?.txt | xargs basename)
      aws s3 sync logs/$PROFILE/logs/$shard/$src ${S3URL} &> /dev/null
   elif [ $src = "all" ]; then
      aws s3 sync logs/$PROFILE/logs ${S3URL} &> /dev/null
   else
      aws s3 sync logs/$PROFILE/logs/shard${src} ${S3URL} &> /dev/null
   fi

   echo $S3URL
}

function download_logs
{
   local shard=$1

   if [ "$shard" = "all" ]; then
      for s in $(seq 0 $(( ${configs[benchmark.shards]} - 1 ))); do
         _download_logs_one_shard ${s}
      done
   else
      _download_logs_one_shard ${shard}
   fi

   sync_log $shard
}

function download_log
{
   local ip=$1
   local shard=$(grep -l $ip logs/${PROFILE}/shard?.txt | xargs basename)
   logging download log of IP: $ip / $shard
   logdir=logs/$PROFILE/logs/${shard}

   mkdir -p $logdir/$ip
   ${SCP} ${ip}:latest/* $logdir/${ip}/

   sync_log $ip
}

function cleanup_log
{
   local ip=$1
   logging cleanup log of IP: $ip
   ${SSH} ${ip} 'rm -f latest/*.gz'
}

function _cleanup_logs_one_shard
{
   local shard=$1
   logging cleanup log in shard: $shard

   cat logs/$PROFILE/shard${shard}.txt | xargs -P ${PARALLEL} -I% bash -c "${SSH} % 'rm -f latest/*.gz'"
}

function cleanup_logs
{
   local shard=$1

   if [ "$shard" = "all" ]; then
      for s in $(seq 0 $(( ${configs[benchmark.shards]} - 1 ))); do
         _cleanup_logs_one_shard ${s}
      done
   else
      _cleanup_logs_one_shard ${shard}
   fi
}

########################################

PARALLEL=50
PROFILE=${HMY_PROFILE:-tiny}
PROFILES=( $(ls $CONFIG_DIR/benchmark-*.json | sed -e "s,$CONFIG_DIR/benchmark-,,g" -e 's/.json//g') )
BENCHMARK_FILE=$CONFIG_DIR/benchmark-${PROFILE}.json
IP=
SHARD=

while getopts ":s:p:P:i:" option; do
   case $option in
      p)
         PROFILE="$OPTARG"
         BENCHMARK_FILE="$CONFIG_DIR/benchmark-${PROFILE}.json"
         [ ! -e $BENCHMARK_FILE ] && errexit "can't find benchmark config file : $BENCHMARK_FILE"
         ;;
      P) PARALLEL="$OPTARG" ;;
      s) SHARD="$OPTARG" ;;
      i) IP="$OPTARG" ;;
      *) usage ;;
   esac
done

shift $(($OPTIND-1))

read_profile $BENCHMARK_FILE

ACTION=${1:-log}

case $ACTION in
   log)
      if [ -n "$IP" ]; then
         if valid_ip "$IP"; then
            download_log "$IP"
         else
            echo invalid IP address: $IP
         fi
      fi
      if [ -n "$SHARD" ]; then
         download_logs "$SHARD"
      fi
      ;;
   cleanup)
      if [ -n "$IP" ]; then
         if valid_ip "$IP"; then
            cleanup_log "$IP"
         else
            echo invalid IP address: $IP
         fi
      fi
      if [ -n "$SHARD" ]; then
         cleanup_logs "$SHARD"
      fi
      ;;
   sync)
      if [ -n "$IP" ]; then
         if valid_ip "$IP"; then
            sync_log "$IP"
         else
            echo invalid IP address: $IP
         fi
      fi
      if [ -n "$SHARD" ]; then
         sync_log "$SHARD"
      fi
      ;;
   *) usage ;;
esac
