#!/usr/bin/env bash

# set -x

function usage
{
   ME=$(basename $0)
   cat<<EOT
Usage: $ME [OPTIONS] ACTIONS

This script automates the benchmark test based on profile.

[OPTIONS]
   -h             print this help message
   -p profile     specify the benchmark profile in $CONFIG directory (default: $PROFILE)
                  supported profiles (${PROFILES[@]})
   -v             verbose output

[ACTIONS]
--- only full automation is support for now ---

   launch         do launch only
   run            run benchmark
   log            download logs
   deinit         sync logs & terminate instances
   all            do everything (default)


[EXAMPLES]

   $ME -p tiny
   $ME -p 10k
   $ME -p 20k

   $ME -p mix10k

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

   if [ "${configs[powerclient]}" == "true" ]; then
      echo ./launch-client-only.sh ${configs[client]} &
   else
      logging using regular client
   fi

   if [ "${configs[powerleader]}" == "true" ]; then
      echo ./launch-client-only.sh ${configs[leader]} &
   else
      logging using regular client
   fi


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
   expense download
}

function analyze_logs
{
   logging analyzing logs ...
   expense analysis
}

function do_deinit
{
   logging deinit ...
   expense deinit
}

function read_profile
{
   logging reading profile $PROFILE
   local file=$CONFIG/benchmark-$PROFILE.json
   [ ! -e $file ] && errexit "can't find profile: $PROFILE"

   keys=( description num_vm_aws num_vm_azure shards powerclient client powerleader leader master duration parallel dashboard logs.leader logs.client logs.validator logs.soldier )

   for k in ${keys[@]}; do
      configs[$k]=$($JQ .$k $file)
   done

   verbose ${configs[@]}
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
PROFILE=tiny
CONFIG=configs
PROFILES=( $(ls $CONFIG/benchmark-*.json | sed -e "s,$CONFIG/benchmark-,,g" -e 's/.json//g') )
VERBOSE=
THEPWD=$(pwd)
JQ='jq -M'

declare -A configs

while getopts "hp:v" option; do
   case $option in
      h) usage ;;
      p) PROFILE=$OPTARG ;;
      v) VERBOSE=1 ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$*

if [ -z "$ACTION" ]; then
   ACTION=all
fi

case $ACTION in
   all) main ;;
   launch) do_launch ;;
   run) do_run ;;
   log) download_logs ;;
   deinit) do_deinit ;;
esac

exit 0

