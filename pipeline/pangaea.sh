#!/usr/bin/env bash

# set -x

shard_ip=( 52.90.150.67 3.16.123.229 52.51.16.220 54.213.145.224 )

function usage
{
   ME=$(basename $0)
   cat<<EOT
Usage: $ME [OPTIONS] ACTIONS

This script automates the benchmark test based on profile.

[OPTIONS]
   -h                      print this help message
   -p profile              specify the profile (default: $PROFILE)
   -v                      verbose output
   -d logdir               the log directory

[ACTIONS]

   r53                     generate the r53 script based on shard{0..3}.txt files
   log                     download the pangaea logs
   block                   print out the latest block number
   find                    find the internal node based on blskey


[EXAMPLES]

   $ME -p $PROFILE r53

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

function do_launch
{
   logging launching instances ...
   expense launch
}

function do_run
{
   logging run benchmark
   expense run
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
   NUM_IP=25
   for shard in $(seq 0 3); do
      local file=$LOGDIR/shard${shard}.txt
      echo python3 r53update.py p $shard $(sort -R $file | head -n $NUM_IP | tr "\n" " ")
   done
}

# find internal IP based on blskey
function find_int_ip {
   local shard=$1
   rm -f s${shard}.stop.ip
   for key in $(cat $PROFILE/online-ext-keys-sorted-${shard}.txt); do
      soldier=$(grep -l $key $LOGDIR/validator/soldier-*.log)
      intip=$(basename $soldier | sed 's,soldier-\(.*\).log,\1,' )
      echo $intip >> s${shard}.stop.ip
   done
}

function main
{
   read_profile
   do_launch
   do_run
   download_logs
   analyze_logs
   do_deinit
}

######### VARIABLES #########
PROFILE=pangaea
CONFIG=configs
LOGDIR=logs/$PROFILE
VERBOSE=
THEPWD=$(pwd)
JQ='jq -r -M'

while getopts "hp:vd:" option; do
   case $option in
      h) usage ;;
      p) PROFILE=$OPTARG ;;
      v) VERBOSE=1 ;;
      d) LOGDIR=$OPTARG ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$1
shift

if [ -z "$ACTION" ]; then
   ACTION=all
fi

case $ACTION in
   run) do_run ;;
   log) download_logs ;;
   r53) generate_r53_script $* ;;
   block) cal_block ;;
   find) find_int_ip $* ;;
esac

exit 0

