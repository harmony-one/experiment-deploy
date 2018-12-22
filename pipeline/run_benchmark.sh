#!/usr/bin/env bash

#TODO: parameter validation

set -o pipefail
set -x

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
   -A attacked_mode  enable attacked mode support (default mode: $ATTACK)
   -C cross_ratio    enable cross_shard_ratio (default ratio: $CROSSTX)
   -B beacon IP      IP address of beacon chain (default: $BEACONIP)
   -b beacon port    port number of beacon chain (default: $BEACONPORT)
   -m minpeer        minimum number of peers required to start consensus (default: $MINPEER)
   -c                invoke client node (default: $CLIENT)

ACTIONS:
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

function logging
{
   echo $(date) : $@
   SECONDS=0
}

function errexit
{
   logging "$@ . Exiting ..."
   exit -1
}

function read_profile
{
   BUCKET=$($JQ .bucket $CONFIG_FILE)
   FOLDER=$($JQ .folder $CONFIG_FILE)
   SESSION=$($JQ .sessionID $CONFIG_FILE)

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
      init)
      benchmarkArgs="-attacked_mode $ATTACK -bc $BEACONIP -bc_port $BEACONPORT -min_peers $MINPEER"
      txgenArgs="-duration -1 -cross_shard_ratio $CROSSTX -bc $BEACONIP -bc_port $BEACONPORT"
      if [ -n "$DASHBOARD" ]; then
         benchmarkArgs+=" $DASHBOARD"
      fi
      if [ "$CLIENT" == "true" ]; then
         CLIENT_JSON=',"role":"client"'
      fi
      cat>$LOGDIR/$cmd/$cmd.json<<EOT
{
   "ip":"127.0.0.1",
   "port":"9000",
   "sessionID":"$SESSION",
   "benchmarkArgs":"$benchmarkArgs",
   "txgenArgs":"$txgenArgs"
   $CLIENT_JSON
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

# send commands to leaders at first
   local num_leader=$(grep leader $DIST | wc -l)
   for n in $(seq 1 $num_leader); do
      local ip=${NODEIPS[$n]}
      CMD=$"curl -X GET -s http://$ip:1${PORT[$ip]}/$cmd -H \"Content-Type: application/json\""

      case $cmd in
         init|update)
            CMD+=$" -d@$LOGDIR/$cmd/$cmd.json" ;;
      esac

      [ -n "$VERBOSE" ] && echo $n =\> $CMD
      $TIMEOUT -s SIGINT 20s $CMD > $LOGDIR/$cmd/$cmd.$n.$ip.log
   done

   while [ $end -lt $NUM_NODES ]; do
      start=$(( $PARALLEL * $group + $num_leader + 1))
      end=$(( $PARALLEL + $start - 1 ))

      if [ $end -ge $NUM_NODES ]; then
         end=$NUM_NODES
      fi

      echo processing group: $group \($start to $end\)

      for n in $(seq $start $end); do
         local ip=${NODEIPS[$n]}
         CMD=$"curl -X GET -s http://$ip:1${PORT[$ip]}/$cmd -H \"Content-Type: application/json\""

         case $cmd in
            init|update)
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

function do_auto
{
   echo TODO
}

#################### VARS ####################
JQ='jq -r -M'
CONFIG_DIR=../configs
PROFILE=tiny
CONFIG_FILE=$CONFIG_DIR/profile-${PROFILE}.json
DIST=distribution_config.txt
PARALLEL=100
VERBOSE=
DASHBOARD=
ATTACK=2
CROSSTX=30
BEACONIP=54.183.5.66
BEACONPORT=9999
MINPEER=10
CLIENT=

declare -A NODES
declare -A NODEIPS
declare -A PORT

#################### MAIN ####################
while getopts "hp:f:i:a:n:vD:A:C:B:b:m:c" option; do
   case $option in
      p)
         PROFILE=$OPTARG
         CONFIG_FILE=$CONFIG_DIR/profile-${PROFILE}.json
         [ ! -e $CONFIG_FILE ] && errexit "can't find config file : $CONFIG_FILE"
         ;;
      f) DIST=$OPTARG ;;
      i) IPS=$OPTARG ;;
      a) APP=$OPTARG ;;
      n) PARALLEL=$OPTARG ;;
      v) VERBOSE=true ;;
      D) DASHBOARD="-metrics_report_url http://$OPTARG/report" ;;
      A) ATTACK=$OPTARG ;;
      C) CROSSTX=$OPTARG ;;
      B) BEACONIP=$OPTARG ;;
      b) BEACONPORT=$OPTARG ;;
      m) MINPEER=$OPTARG ;;
      c) CLIENT=true ;;
      h|?) usage ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$@

read_nodes

case "$ACTION" in
   "ping"|"kill"|"init"|"update") do_simple_cmd $ACTION ;;
   "auto") do_auto ;;
   *) usage ;;
esac
