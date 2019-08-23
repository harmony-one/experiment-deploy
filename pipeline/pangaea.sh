#!/usr/bin/env bash

# set -x

shard_ip=( 34.217.114.178 18.222.73.67 52.23.230.48 34.246.160.23 )

function usage
{
   ME=$(basename $0)
   cat<<EOT
Usage: $ME [OPTIONS] ACTIONS SHARD_ID

This script automates the benchmark test based on profile.

[OPTIONS]
   -h                            print this help message
   -p profile                    specify the profile (default: $PROFILE)
   -v                            verbose output
   -d logdir                     the log directory
   -w workdir                    the workdir (default: $WORKDIR)

[ACTIONS]

   log                           download the pangaea logs
   block                         print out the latest block number
   status                        check pangaea network status (log && block)
   r53 [shard] [file]            generate the r53 script based on [file]
   find [shard] [file]           find the internal node based on blskey in [file]
   exclude [shard] [file]        exclude the IP in [file]
   peer [shard]                  find the external peers in [shard]
   offline [shard] [file]        find all the offline bls keys in the shard excluding [file]
   ma [shard]                    find a list of multiaddresses in the shard


[SHARD_ID]

   the shard id, 0, 1, 2, 3

[EXAMPLES]

# generate r53 update script for shard 0
   $ME -p $PROFILE -w pang/0815 r53 0

EOT
   exit 0
}

function logging
{
   echo $(date) : $@
   SECONDS=0
}

function expense
{
   local step=$1
   local duration=$SECONDS
   logging $step took $(( $duration / 60 )) minutes and $(( $duration % 60 )) seconds
}

function verbose
{
   [ $VERBOSE ] && echo $@
}

function errexit
{
   logging "$@ . Exiting ..."
   exit -1
}

function download_logs
{
   logging download logs ...
   ./go.sh -p pangaea log
   expense download
}

function cal_block
{
   pushd $LOGDIR/leader/tmp_log/log-20190807.210502 
   s=0
   for ip in ${shard_ip[@]}; do
      line=$( tac zerolog-validator-$ip-9000.log | grep -m 1 HOORAY)
      block=$( echo $line | jq .BlockNum )
      time=$( echo $line | jq .time )
      echo ${s}:${block}:$time
      (( s++ ))
   done
   popd
}

# generate the r53 update script
function generate_r53_script
{
   local shard=$1
   local file=${2:-$LOGDIR/shard${shard}.txt}
   NUM_IP=25
   echo python3 r53update.py p $shard $(sort -R $file | head -n $NUM_IP | tr "\n" " ")
}

# find internal IP based on blskey
function find_int_ip
{
   local shard=$1
   local file=${2:-online-ext-keys-sorted-${shard}.txt}
   rm -f s${shard}.stop.ip
   for key in $(cat $file); do
      soldier=$(grep -l $key $LOGDIR/validator/soldier-*.log)
      intip=$(basename $soldier | sed 's,soldier-\(.*\).log,\1,' )
      echo $intip >> s${shard}.stop.ip
   done
}

# exclude some IP
function exclude_ip
{
   local shard=$1
   local file=${2:-s${shard}.stop.ip}
   while read ip; do
      if ! grep -q $ip $file; then
         echo $ip
      fi
   done<$LOGDIR/origin/shard${shard}.txt
}

# find all peers from log files
function find_peer
{
   local shard=$1
   ./peer_log.sh -p $PROFILE -d logs/$PROFILE $shard
   ./ext_peers.sh $shard
}

function find_offline_keys
{
   local shard=$1
   local file=${2:-online-ext-keys-sorted-${shard}.txt}
   i=0
   while read bls; do
      key=$(echo $bls | cut -f1 -d\.)
      shardid=$( expr $i % 4 )
      if [ $shardid == $shard ]; then
         if ! grep -q $key $file; then
            echo $i =\> $key is offline
         fi
      fi
      (( i++ ))
   done<"../configs/pangaea-keys.txt"
}

function find_ma_address
{
   local shard=$1
   while read ip; do
      vlog="$LOGDIR/validator/tmp_log/*/validator-$ip-9000.log"
      ma=$(grep -F -m 1 multiaddress $vlog | $JQ .multiaddress)
      echo $ma
   done<"$LOGDIR/shard${shard}.txt"
}

function check_leader_status
{
   s=0
   echo current time: $(date)
   echo ==========================================
   echo shard : block num : block time
   for ip in ${shard_ip[@]}; do
      block=$(./node_ssh.sh -p pangaea ec2-user@$ip 'tac /home/tmp_log/*/zerolog-validator-*.log | grep -m 1 -F HOORAY | jq .BlockNum')
      time=$(./node_ssh.sh -p pangaea ec2-user@$ip 'tac /home/tmp_log/*/zerolog-validator-*.log | grep -m 1 -F HOORAY | jq .time')
      echo $s : $block : $time
      (( s++ ))
   done
}

######### VARIABLES #########
PROFILE=pangaea
CONFIG=configs
LOGDIR=logs/$PROFILE
WORKDIR=pangaea/$(date +%Y%m%d.%H%M%S)
VERBOSE=
THEPWD=$(pwd)
JQ='jq -r -M'

while getopts "hp:vd:w:" option; do
   case $option in
      h) usage ;;
      p) PROFILE=$OPTARG ;;
      v) VERBOSE=1 ;;
      d) LOGDIR=$OPTARG ;;
      w) WORKDIR=$OPTARG ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$1
shift

if [ -z "$ACTION" ]; then
   ACTION=all
fi

case $ACTION in
   log) download_logs ;;
   block) cal_block ;;
   status) check_leader_status ;;
   r53) generate_r53_script $* ;;
   find) find_int_ip $* ;;
   exclude) exclude_ip $* ;;
   peer) find_peer $* ;;
   offline) find_offline_keys $* ;;
   ma) find_ma_address $* ;;
   *) usage ;;
esac

exit 0

