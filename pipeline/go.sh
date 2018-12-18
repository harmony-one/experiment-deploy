#!/usr/bin/env bash

#set -euxo pipefail
# set -x

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
   -e true/false  enable peer discovery configuration (default: $PEER)

[ACTIONS]
   launch         do launch only
   run            run benchmark
   log            download logs
   deinit         sync logs & terminate instances
   reset          reset dashboard and explorer
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
      LAUNCH_OPT+=' -i raw_ip-client.txt'
      num_clients=$(cat raw_ip-client.txt | wc -l)
   else
      num_clients=1
      logging using regular client
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
   -t ${num_clients} \
   -u ${configs[userdata]} \
   -P $PROFILE \
   ${LAUNCH_OPT}

   if [ ${configs[client.num_vm]} -gt 0 ]; then
      cat instance_ids_output-client.txt >> instance_ids_output.txt
      cat instance_output-client.txt >> instance_output.txt
      rm instance_ids_output-client.txt instance_output-client.txt raw_ip-client.txt &
   fi

   if [ ${configs[leader.num_vm]} -gt 0 ]; then
      cat instance_ids_output-leader.txt >> instance_ids_output.txt
      cat instance_output-leader.txt >> instance_output.txt
      rm instance_ids_output-leader.txt instance_output-leader.txt raw_ip-leader.txt &
   fi

   echo sleeping ${configs[flow.wait_for_launch]} ...
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
      echo sleeping 60s ...
      sleep 60
      (( r++ ))
      prev_total=$total
   done

   expense launch
}

function do_launch_beacon
{
   logging launch beacon node
   ./beacon.sh -G -p ${configs[beacon.port]} -s ${configs[benchmark.shards]} -f ${FOLDER}
   expense beacon
}

function do_run
{
   logging run benchmark
   local RUN_OPTS=

   if [ "${configs[benchmark.dashboard]}" == "true" ]; then
      RUN_OPTS+=" -D ${configs[dashboard.server]}:${configs[dashboard.port]}"
   fi

   RUN_OPTS+=" -C ${configs[benchmark.crosstx]}"
   RUN_OPTS+=" -A ${configs[benchmark.attacked_mode]}"
   RUN_OPTS+=" -B ${configs[beacon.server]}"
   RUN_OPTS+=" -b ${configs[beacon.port]}"
   RUN_OPTS+=" -m ${configs[benchmark.minpeer]}"

# no need to do config for peer discovery mode
   if [ "$PEER" == "false" ]; then
      ./run_benchmark.sh -n ${configs[parallel]} -p $PROFILE config
      sleep 3
   else
      RUN_OPTS+=" -P -peer_discovery"
   fi

   [ $VERBOSE ] && RUN_OPTS+=" -v"

   ./run_benchmark.sh -n ${configs[parallel]} ${RUN_OPTS} -p $PROFILE init

   [ ! -e $CONFIG_FILE ] && errexit "can't find profile config file : $CONFIG_FILE"
   TS=$(cat $CONFIG_FILE | $JQ .sessionID)

# assuming we are running on AWS instance
   if [ "${configs[txgen.enable]}" == "true" ]; then
      if [ "${configs[txgen.ip]}" == "myip" ]; then
         MYIP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
      else
         MYIP=${configs[txgen.ip]}
      fi
      aws s3 cp s3://$BUCKET/$FOLDER/txgen txgen
      chmod +x txgen
      echo "running txgen"
      ./txgen -bc ${configs[beacon.server]} -bc_port ${configs[beacon.port]} -ip $MYIP -port ${configs[txgen.port]} -peer_discovery -log_folder logs/${TS} -duration ${configs[benchmark.duration]} > logs/${TS}/txgen-${TS}.log 2>&1 &
   fi

   echo sleeping ${configs[benchmark.duration]} ...
   sleep ${configs[benchmark.duration]}

#  no need to kill as we will terminate the instances
#   ./run_benchmark.sh -p $PROFILE kill &

   expense run
}

function download_logs
{
   logging download logs ...
   if [ "${configs[logs.leader]}" == "true" ]; then
      ./dl-soldier-logs.sh -s $TS -g leader benchmark
   fi
   if [ "${configs[logs.client]}" == "true" ]; then
      ./dl-soldier-logs.sh -s $TS -g client benchmark
   fi
   if [ "${configs[logs.validator]}" == "true" ]; then
      ./dl-soldier-logs.sh -s $TS -g validator benchmark
   fi
   if [ "${configs[logs.soldier]}" == "true" ]; then
      ./dl-soldier-logs.sh -s $TS -g leader soldier &
      ./dl-soldier-logs.sh -s $TS -g client soldier &
      ./dl-soldier-logs.sh -s $TS -g validator soldier &
   fi
   wait
   expense download
}

function analyze_logs
{
   local DIR=logs/$TS/leader/tmp_log/log-$TS

   logging analyzing logs in $DIR ...
   pushd $DIR
   ${THEPWD}/cal_tps.sh | tee ${THEPWD}/logs/$TS/tps.txt
   popd
   expense analysis
}

function do_sync_logs
{
   wait
   aws s3 sync logs/$TS s3://harmony-benchmark/logs/$TS 2>&1 > /dev/null
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

   keys=( description aws.profile azure.num_vm azure.regions leader.regions leader.num_vm leader.type client.regions client.num_vm client.type benchmark.shards benchmark.duration benchmark.dashboard benchmark.crosstx benchmark.attacked_mode logs.leader logs.client logs.validator logs.soldier parallel dashboard.server dashboard.port dashboard.reset userdata flow.wait_for_launch beacon.server beacon.port beacon.user beacon.key benchmark.minpeer explorer.server explorer.port explorer.reset txgen.ip txgen.port txgen.enable )

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
      curl -X POST http://${configs[dashboard.server]}:${configs[dashboard.port]}/reset -H "content-type: application/json" -d '{"secret":"426669"}'
   fi
   if [ "${configs[explorer.reset]}" == "true" ]; then
      echo "resetting explorer ..."
      echo curl -X POST http://${configs[explorer.server]}:${configs[explorer.port]}/reset -H "content-type: application/json" -d '{"secret":"426669"}'
   fi
}

function do_all
{
   do_launch_beacon
   do_launch
   do_reset
   do_run
   download_logs
   analyze_logs
   do_sync_logs
   if [ "$KEEP" == "false" ]; then
      do_deinit
   fi
}

######### VARIABLES #########
PROFILE=1k
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
PEER=true
TAG=${WHOAMI:-USER}
JQ='jq -M -r'

declare -A configs

while getopts "hp:vke:" option; do
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
      e) PEER=$OPTARG ;;
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
   launch)
         do_launch ;;
   run)  
         do_launch_beacon
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
