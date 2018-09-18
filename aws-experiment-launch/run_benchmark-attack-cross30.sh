#!/usr/bin/env bash

#TODO: parameter validation

set -o pipefail

if [ "$(uname -s)" == "Darwin" ]; then
   TIMEOUT=gtimeout
else
   TIMEOUT=timeout
fi


function usage
{
   ME=$(basename $0)
   cat<<EOT
Usage: $ME [OPTIONS] ACTIONS

OPTIONS:
   -h                print this usage
   -p profile        name of test profile (default: $PROFILE)
   -f distribution   name of the distribution file (default: $DIST)
   -i ip_addresses   ip addresses of the soldiers to run command
                     delimited by ,
   -a application    name of the application to be updated
   -p testplan       file name of the test plan
   -n num            parallel process num in a group (default: $PARALLEL)
   -v                verbose
   -D dashboard_ip   enable dashboard support, specify the ip address of dashboard server (default: $DASHBOARD)
   -A                enable attack support, (default is on: $ATTACK)

ACTIONS:
   gen               generate test file based on profile (TODO)
   auto              automate the test execution based on test plan (TODO)
   ping              ping each soldier
   config            configure distribution_config to each soldier
   init              start benchmark test, after config
   kill              kill all running benchmark/txgen 
   update            update certain/all binaries on solider(s)

EXAMPLES:

   $ME -i 10.10.1.1,10.10.1,2 -a benchmark update
   $ME -f dist1.txt -d myjason-format config
EOT
   exit 0
}

function read_profile
{
   if [ ! -f $PROFILE ]; then
      echo ERROR: $PROFILE does not exist or not readable
      exit 1
   fi

   BUCKET=$($JQ .bucket $PROFILE)
   FOLDER=$($JQ .folder $PROFILE)
   SESSION=$($JQ .sessionID $PROFILE)

   LOGDIR=${CACHE}logs/$SESSION

   mkdir -p $LOGDIR
}

function read_nodes
{
   read_profile

   if [ ! -f $DIST ]; then
      echo ERROR: $DIST does not exist or not readable
      return 0
   fi

   n=1
   while read line; do
      fields=( $(echo $line) )
      NODEIPS[$n]=${fields[0]}
      NODES[${fields[0]}]=${fields[2]}
      PORT[${fields[0]}]=${fields[1]}
      (( n++ ))
   done < $DIST

   NUM_NODES=${#NODES[@]}
   NUM_GROUPS=$(( $NUM_NODES / $PARALLEL ))
   echo INFO: read ${NUM_NODES} nodes from $DIST
}

function do_simple_cmd
{
   local cmd=$1

   mkdir -p $LOGDIR/$cmd

   end=0
   group=0
   case $cmd in
      config) cat>$LOGDIR/$cmd/$cmd.json<<EOT
{
   "sessionID":"$SESSION",
   "configURL":"http://$BUCKET.s3.amazonaws.com/$FOLDER/distribution_config.txt"
}
EOT
;;
      init) cat>$LOGDIR/$cmd/$cmd.json<<EOT
{
   "ip":"127.0.0.1",
   "port":"9000",
   "benchmarkArgs":"$DASHBOARD $ATTACK",
   "txgenArgs":"-duration -1 $CROSSTX"
}
EOT
;;
      update)
            if [ -z "$APP" ]; then
               echo ERROR: no application name specified
               exit 1
            fi
            cat>$LOGDIR/$cmd/$cmd.json<<EOT
{
   "bucket":"$BUCKET",
   "folder":"$FOLDER",
   "file":"$APP"
}
EOT
;;
   esac
 
   SECONDS=0
   while [ $end -lt $NUM_NODES ]; do
      start=$(( $PARALLEL * $group + 1 ))
      end=$(( $PARALLEL + $start - 1 ))

      if [ $end -ge $NUM_NODES ]; then
         end=$NUM_NODES
      fi

      echo processing group: $group \($start to $end\)

      for n in $(seq $start $end); do
         local ip=${NODEIPS[$n]}
         CMD=$"curl -X GET -s http://$ip:1${PORT[$ip]}/$cmd -H \"Content-Type: application/json\""

         case $cmd in
            config|init|update)
               CMD+=$" -d@$LOGDIR/$cmd/$cmd.json" ;;
         esac

         [ -n "$VERBOSE" ] && echo $n =\> $CMD
         $TIMEOUT -s SIGINT 20s $CMD > $LOGDIR/$cmd/$cmd.$n.$ip.log &
      done 
      wait
      (( group++ ))
   done
   duration=$SECONDS

   succeeded=$(find $LOGDIR/$cmd -name $cmd.*.log -type f -exec grep Succeeded {} \; | wc -l)
   failed=$(( $NUM_NODES - $succeeded ))

   echo $(date): $cmd succeeded/$succeeded, failed/$failed nodes, $(($duration / 60)) minutes and $(($duration % 60)) seconds

   rm -rf $LOGDIR/$cmd
}

function do_update
{
   if [ -z "$APP" ]; then
      echo ERROR: no application name specified
      exit 1
   fi

   succeeded=0
   failed=0
   date
   for n in "${!NODES[@]}"; do
      res=$(curl -s -XGET http://$n:1${PORT[$n]}/update \
      --header "content-type: application/json" \
      -d "{\"bucket\":\"$BUCKET\",\"folder\":\"$FOLDER\",\"file\":\"$APP\"}" )

      if [ "$res" == "Succeeded" ]; then
         (( succeeded++ ))
      else
         echo ERROR: $res
         (( failed++ ))
      fi
   done

   echo $(date): Update succeeded/$succeeded, failed/$failed nodes
}

function generate_tests
{
   echo todo
}

#################### VARS ####################
JQ='jq -r -M'
PROFILE=configs/profile.json
DIST=distribution_config.txt
PARALLEL=100
VERBOSE=
DASHBOARD=
ATTACK="-attacked_mode 2"

declare -A NODES
declare -A NODEIPS
declare -A PORT

#################### MAIN ####################
while getopts "hp:f:i:a:n:vD:AC" option; do
   case $option in
      p) PROFILE=$OPTARG ;;
      f) DIST=$OPTARG ;;
      i) IPS=$OPTARG ;;
      a) APP=$OPTARG ;;
      n) PARALLEL=$OPTARG ;;
      v) VERBOSE=true ;;
      D) DASHBOARD="-metrics_report_url http://$OPTARG/report" ;;
      A) ATTACK="-attacked_mode 2" ;;
      C) CROSSTX="-cross_shard_ratio 30" ;;
      h|?) usage ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$@

case "$ACTION" in
   "gen") read_nodes; generate_tests ;;
   "ping"|"kill"|"config"|"init"|"update") read_nodes; do_simple_cmd $ACTION ;;
   "auto") read_nodes; do_auto ;;
   *) usage ;;
esac
