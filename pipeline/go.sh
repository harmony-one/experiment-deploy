#!/usr/bin/env bash

#set -euxo pipefail
# set -x

RETRY_LAUNCH_TIME=10

#############################
function usage
{
   ME=$(basename $0)
   cat<<EOT
Usage: $ME [OPTIONS] ACTIONS

This script automates the benchmark test based on profile.

[OPTIONS]
   -h             print this help message
   -p profile     specify the benchmark profile in $CONFIG_DIR directory (default: $PROFILE)
                  supported profiles (${PROFILES[@]})
   -v             verbose output
   -k             keep all the instances, skip deinit (default: $KEEP)

[ACTIONS]
   launch         do launch only
   run            run benchmark
   log            download logs
   deinit         sync logs & terminate instances
   reset          reset dashboard and explorer
   bootnode       launch bootnode(s) only
   all            do everything (default)


[EXAMPLES]

   $ME -p tiny
   $ME -p debug
   $ME -p devnet -k

   $ME -p testnet log

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

function _join
{
   local IFS="$1"; shift; echo "$*"; 
}

function do_launch
{
   logging launching instances ...

   local LAUNCH_OPT=

   if [ ${configs[client.num_vm]} -gt 0 ]; then
      logging launching ${configs[client.num_vm]} non-standard client: ${configs[client.type]}
      ../bin/instance \
      -config_dir $CONFIG_DIR \
      -instance_count ${configs[client.num_vm]} \
      -instance_type ${configs[client.type]} \
      -launch_region ${configs[client.regions]} \
      -ip_file raw_ip-client.txt \
      -output instance_ids_output-client.txt \
      -tag_file instance_output-client.txt \
      -tag ${TAG}-powerclient \
      -launch_profile launch-$PROFILE.json
   fi

   if [ ${configs[leader.num_vm]} -gt 0 ]; then
      logging launching ${configs[leader.num_vm]} non-standard leader: ${configs[leader.type]}
      ../bin/instance \
      -config_dir $CONFIG_DIR \
      -instance_count ${configs[leader.num_vm]} \
      -instance_type ${configs[leader.type]} \
      -launch_region ${configs[leader.regions]} \
      -ip_file raw_ip-leader.txt \
      -output instance_ids_output-leader.txt \
      -tag_file instance_output-leader.txt \
      -tag ${TAG}-leader \
      -launch_profile launch-$PROFILE.json
      LAUNCH_OPT+=' -l raw_ip-leader.txt'
      num_leader=$(cat raw_ip-leader.txt | wc -l)
   fi

   ./deploy.sh \
   -C ${configs[azure.num_vm]} \
   -s ${configs[benchmark.shards]} \
   -t 0 \
   -u ${configs[userdata]} \
   -P $PROFILE \
   ${LAUNCH_OPT}

   if [ ${configs[client.num_vm]} -gt 0 ]; then
      ip=$(cat raw_ip-client.txt | awk '{ print $1 }')
      region_code=$($JQ ".regions[] | select (.name | contains(\"${configs[client.regions]}\")) | .code" $CONFIG_DIR/aws.json)
      echo "$ip 9000 client 0 $region_code-$USERID" > client.config.txt
      rm instance_ids_output-client.txt instance_output-client.txt raw_ip-client.txt &
   fi

   if [ ${configs[leader.num_vm]} -gt 0 ]; then
      cat instance_ids_output-leader.txt >> instance_ids_output.txt
      cat instance_output-leader.txt >> instance_output.txt
      rm instance_ids_output-leader.txt instance_output-leader.txt raw_ip-leader.txt &
   fi

   echo waiting for instances launch ${configs[flow.wait_for_launch]} ...
   sleep  ${configs[flow.wait_for_launch]}

   RETRY=8
   local r=0
   local prev_total=0

   local expected=$(wc -l raw_ip.txt | cut -f 1 -d ' ')
   while [ $r -le $RETRY ]; do
      local total=$(./aws-instances.sh -g $TAG | tail -n 1 | cut -f 1 -d ' ')
      if [ $prev_total -eq $total ]; then
         echo "no change on number of running instances, breaking retry loop - $r"
         break
      fi
      if [ $total -ge $expected ]; then
         echo "all $expected instances are in running state"
         break
      else
         echo "$total/$expected instances are in running state"
      fi
      echo sleeping ${RETRY_LAUNCH_TIME}s for retry ...
      sleep ${RETRY_LAUNCH_TIME}
      (( r++ ))
      prev_total=$total
   done

   expense launch
}

function do_launch_beacon
{
   if [ "${configs[beacon.enable]}" != "true" ]; then
      echo "skipping launch beacon node"
      return
   fi

   logging launch beacon node
   ./beacon.sh -G -p ${configs[beacon.port]} -s ${configs[benchmark.shards]} -f ${FOLDER}
   expense beacon
   BC_MA=$(cat bc-ma.txt)
}

function do_launch_bootnode
{
   BN=${1:-bootnode}
   if [ "${configs[${BN}.enable]}" != "true" ]; then
      echo "skipping launch bootnode: ${BN}"
      return
   fi

   logging launch $BN node - $PROFILE profile
   ./bootnode.sh -G -p ${configs[${BN}.port]} -f ${FOLDER} -S ${configs[${BN}.server]} -k ${configs[${BN}.key]} -P $PROFILE -n $BN
   expense bootnode
   BN_MA+="$(cat ${BN}-ma.txt),"
}

function do_run
{
   logging run benchmark
   local RUN_OPTS=

   if [ "${configs[benchmark.dashboard]}" == "true" ]; then
      RUN_OPTS+=" -D ${configs[dashboard.server]}:${configs[dashboard.port]}"
   fi

   if [ -n "$BC_MA" ]; then
      RUN_OPTS+=" -M $BC_MA"
   else
      RUN_OPTS+=" -B ${configs[beacon.server]}"
      RUN_OPTS+=" -b ${configs[beacon.port]}"
   fi

   if [ "${configs[libp2p]}" == "true" ]; then
      RUN_OPTS+=" -P true"
   fi

   BN_MA=$(echo $BN_MA | sed s/,$//)
   if [ -n "$BN_MA" ]; then
      RUN_OPTS+=" -N $BN_MA"
   fi

   RUN_OPTS+=" -C ${configs[benchmark.crosstx]}"
   RUN_OPTS+=" -A ${configs[benchmark.attacked_mode]}"
   RUN_OPTS+=" -m ${configs[benchmark.minpeer]}"

   [ $VERBOSE ] && RUN_OPTS+=" -v"

   ./run_benchmark.sh -n ${configs[parallel]} ${RUN_OPTS} -p $PROFILE init

# An example on how to call wallet on each node to generate transactions
#   if [ "${configs[wallet.enable]}" == "true" ]; then
#      ./run_benchmark.sh -n ${configs[parallel]} -p $PROFILE wallet
#   fi

   [ ! -e $CONFIG_FILE ] && errexit "can't find profile config file : $CONFIG_FILE"
   TS=$(cat $CONFIG_FILE | $JQ .sessionID)

   # save the beacon chain multiaddress
   mv -f bc-ma.txt logs/$TS
   mv -f bootnode*-ma.txt logs/$TS

   if [ "${configs[txgen.enable]}" == "true" ]; then
      if [ ${configs[client.num_vm]} -gt 0 ]; then
         echo "running txgen on $(cat client.config.txt)"
         ./run_benchmark.sh -n 1 ${RUN_OPTS} -p $PROFILE -f client.config.txt -c init
         cp client.config.txt logs/$TS
         rm -f client.config.txt
      fi
   fi

   echo waiting for txgen benchmarking ${configs[benchmark.duration]} ...
   sleep ${configs[benchmark.duration]}

#  no need to kill as we will terminate the instances
#   ./run_benchmark.sh -p $PROFILE kill &

   expense run
}

function download_logs
{
   if [ -z $TS ]; then
      [ ! -e $CONFIG_FILE ] && errexit "can't find profile config file : $CONFIG_FILE"
      TS=$(cat $CONFIG_FILE | $JQ .sessionID)
   fi

   logging download logs ...
   ./dl-soldier-logs.sh -s $TS -g leader -D logs/$TS/distribution_config.txt version

   if [ "${configs[logs.leader]}" == "true" ]; then
      ./dl-soldier-logs.sh -s $TS -g leader -D logs/$TS/distribution_config.txt benchmark
      ./dl-soldier-logs.sh -s $TS -g validator -D logs/$TS/distribution_config.txt soldier
   fi
   if [[ "${configs[logs.client]}" == "true" && ${configs[client.num_vm]} -gt 0 ]]; then
      ./dl-soldier-logs.sh -s $TS -g client -D logs/$TS/client.config.txt soldier
      ./dl-soldier-logs.sh -s $TS -g client -D logs/$TS/client.config.txt benchmark
   fi
   if [ "${configs[logs.validator]}" == "true" ]; then
      ./dl-soldier-logs.sh -s $TS -g validator -D logs/$TS/distribution_config.txt benchmark
   fi
   if [ "${configs[logs.soldier]}" == "true" ]; then
      ./dl-soldier-logs.sh -s $TS -g leader -D logs/$TS/distribution_config.txt soldier &
   fi
   wait
   expense download
   rm -f logs/$PROFILE
   ln -sf $TS logs/$PROFILE
}

function analyze_logs
{
   if [ -z $TS ]; then
      [ ! -e $CONFIG_FILE ] && errexit "can't find profile config file : $CONFIG_FILE"
      TS=$(cat $CONFIG_FILE | $JQ .sessionID)
   fi

   find logs/$TS -name leader-*.log > logs/$TS/all-leaders.txt
   find logs/$TS -name validator-*.log > logs/$TS/all-validators.txt
   logging analyzing logs in $(cat logs/$TS/all-leaders.txt)
   ${THEPWD}/cal_tps.sh logs/$TS/all-leaders.txt logs/$TS/all-validators.txt | tee ${THEPWD}/logs/$TS/tps.txt
   expense analysis
}

function do_sync_logs
{
   wait
   aws s3 sync logs/$TS s3://harmony-benchmark/logs/$TS 2>&1 > /dev/null
   echo s3://harmony-benchmark/logs/$TS
}

function do_deinit
{
   logging deinit ...
   if [ ${configs[azure.num_vm]} -gt 0 ]; then
      ../azure/go-az.sh deinit &
   fi

#   TAGS=( $(cat instance_output.txt  | cut -f1 -d' ' | sed s,^[1-9]-,, | sort -u) )
#   for tag in ${TAGS[@]}; do
#      ./aws-instances.sh -g $tag
#      ./aws-instances.sh -G delete
#   done
#   ./terminate_instances.py 2>&1 > /dev/null &

   ./aws-instances.sh -G delete
   rm -f *.ids

   wait
   expense deinit
   cat ${THEPWD}/logs/$TS/tps.txt
}

function read_profile
{
   logging reading benchmark config file: $BENCHMARK_FILE

   keys=( description libp2p aws.profile azure.num_vm azure.regions leader.regions leader.num_vm leader.type client.regions client.num_vm client.type benchmark.shards benchmark.duration benchmark.dashboard benchmark.crosstx benchmark.attacked_mode logs.leader logs.client logs.validator logs.soldier parallel dashboard.server dashboard.name dashboard.port dashboard.reset userdata flow.wait_for_launch beacon.server beacon.port beacon.user beacon.key beacon.enable benchmark.minpeer explorer.server explorer.name explorer.port explorer.reset txgen.ip txgen.port txgen.enable bootnode.port bootnode.server bootnode.key bootnode.enable bootnode1.port bootnode1.server bootnode1.key bootnode1.enable wallet.enable )

   for k in ${keys[@]}; do
      configs[$k]=$($JQ .$k $BENCHMARK_FILE)
   done

   echo "generating userdata file"
   sed "-e s,^BUCKET=.*,BUCKET=${BUCKET}," -e "s,^FOLDER=.*,FOLDER=${FOLDER}/," $USERDATA > $USERDATA.aws
   verbose ${configs[@]}
}

function do_reset
{
   if [ "${configs[dashboard.reset]}" == "true" ]; then
      echo "resetting dashboard ..."
      echo curl -X POST https://${configs[dashboard.name]}:${configs[dashboard.port]}/reset -H "content-type: application/json" -d '{"secret":"426669"}'
      curl -X POST https://${configs[dashboard.name]}:${configs[dashboard.port]}/reset -H 'content-type: application/json' -d '{"secret":"426669"}'
   fi
   if [ "${configs[explorer.reset]}" == "true" ]; then
      echo "resetting explorer ..."
      echo curl -X POST https://${configs[explorer.name]}:${configs[explorer.port]}/reset -H "content-type: application/json" -d '{"secret":"426669"}'
      curl -X POST https://${configs[explorer.name]}:${configs[explorer.port]}/reset -H 'content-type: application/json' -d '{"secret":"426669"}'
   fi
}

function do_all
{
   do_launch_beacon
   do_launch_bootnode
   do_launch_bootnode bootnode1
   do_launch
   do_run
   do_reset
   download_logs
   analyze_logs
   do_sync_logs
   if [ "$KEEP" == "false" ]; then
      do_deinit
   fi
}

######### VARIABLES #########
PROFILE=tiny
ROOTDIR=$(dirname $0)/..
CONFIG_DIR=$(realpath $ROOTDIR)/configs
PROFILES=( $(ls $CONFIG_DIR/benchmark-*.json | sed -e "s,$CONFIG_DIR/benchmark-,,g" -e 's/.json//g') )
CONFIG_FILE=$CONFIG_DIR/profile-${PROFILE}.json
BENCHMARK_FILE=$CONFIG_DIR/benchmark-${PROFILE}.json
BUCKET=unique-bucket-bin
USERID=${WHOAMI:-$USER}
FOLDER=$USERID
USERDATA=$CONFIG_DIR/userdata-soldier-http.sh
VERBOSE=
THEPWD=$(pwd)
KEEP=false
TAG=${WHOAMI:-USER}
JQ='jq -M -r'

declare -A configs

while getopts "hp:vk" option; do
   case $option in
      h) usage ;;
      p)
         PROFILE=$OPTARG
         CONFIG_FILE=$CONFIG_DIR/profile-${PROFILE}.json
         BENCHMARK_FILE=$CONFIG_DIR/benchmark-${PROFILE}.json
         [ ! -e $BENCHMARK_FILE ] && errexit "can't find benchmark config file : $BENCHMARK_FILE"
         ;;
      v) VERBOSE=1 ;;
      k) KEEP=true ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$*

if [ -z "$ACTION" ]; then
   ACTION=all
fi

read_profile
case $ACTION in
   all)  
         do_all ;;
   bootnode)
         do_launch_bootnode
         do_launch_bootnode bootnode1 ;;
   launch)
         do_launch ;;
   run)  
         do_launch_beacon
         do_launch_bootnode
         do_launch_bootnode bootnode1
         do_run ;;
   log)  
         download_logs
         analyze_logs
         do_sync_logs ;;
   deinit)
         do_deinit ;;
   reset)
         do_reset ;;
esac

exit 0
