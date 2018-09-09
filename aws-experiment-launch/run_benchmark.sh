#!/bin/bash

set -o pipefail

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
}

function read_nodes
{
   read_profile

   if [ ! -f $DIST ]; then
      echo ERROR: $DIST does not exist or not readable
      return 0
   fi

   while read line; do
      fields=( $(echo $line) )
      NODES[${fields[0]}]=${fields[2]}
      PORT[${fields[0]}]=${fields[1]}
   done < $DIST

   echo INFO: read ${#NODES[@]} nodes from $DIST
}

function do_simple_cmd
{
   local cmd=$1

   succeeded=0
   failed=0
   date
   for n in "${!NODES[@]}"; do
      res=$(curl -s http://$n:1${PORT[$n]}/$cmd)
      if [ "$res" == "Succeeded" ]; then
         (( succeeded++ ))
      else
         (( failed++ ))
      fi
   done

   echo $(date): Ping succeeded/$succeeded, failed/$failed nodes
}

function do_config
{
   succeeded=0
   failed=0
   date
   for n in "${!NODES[@]}"; do
      res=$(curl -s -XGET http://$n:1${PORT[$n]}/config \
      --header "content-type: application/json" \
      -d "{\"sessionID\":\"$SESSION\",\"configURL\":\"http://$BUCKET.s3.amazonaws.com/$FOLDER/distribution_config.txt\"}" )

      if [ "$res" == "Succeeded" ]; then
         (( succeeded++ ))
      else
         echo ERROR: $res
         (( failed++ ))
      fi
   done

   echo $(date): Config succeeded/$succeeded, failed/$failed nodes
}

function do_init
{
   succeeded=0
   failed=0
   date
   for n in "${!NODES[@]}"; do
      res=$(curl -s -XGET http://$n:1${PORT[$n]}/init \
      --header "content-type: application/json" \
      -d "{\"ip\":\"127.0.0.1\",\"port\":\"9000\",\"benchmarkArgs\":\"\",\"txgenArgs\":\"\"}" )

      if [ "$res" == "Done init" ]; then
         (( succeeded++ ))
      else
         echo ERROR: $res
         (( failed++ ))
      fi
   done

   echo $(date): Init succeeded/$succeeded, failed/$failed nodes
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
declare -A NODES
declare -A PORT

#################### MAIN ####################
while getopts "hp:f:i:a:" option; do
   case $option in
      p) PROFILE=$OPTARG ;;
      f) DIST=$OPTARG ;;
      i) IPS=$OPTARG ;;
      a) APP=$OPTARG ;;
      h|?) usage ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$@

case "$ACTION" in
   "gen") read_nodes; generate_tests ;;
   "ping") read_nodes; do_simple_cmd ping ;;
   "config") read_nodes; do_config ;;
   "update") read_nodes; do_update ;;
   "kill") read_nodes; do_simple_cmd kill ;;
   "init") read_nodes; do_init ;;
   "auto") read_nodes; do_auto ;;
   *) usage ;;
esac
