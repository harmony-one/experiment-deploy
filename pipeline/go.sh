#!/usr/bin/env bash

#set -euxo pipefail
# set -x

unset -v progname progdir
progname="${0##*/}"
case "${0}" in
*/*) progdir="${0%/*}";;
*) progdir=".";;
esac


. "${progdir}/util.sh"
. "${progdir}/common.sh"

RETRY_LAUNCH_TIME=10

#############################
function usage
{
   ME=$(basename $0)
   cat<<EOT
Usage: $ME [OPTIONS] ACTIONS

This script automates the benchmark test based on profile.

[OPTIONS]
   -h                print this help message
   -p profile        specify the benchmark profile in $CONFIG_DIR directory (default: $PROFILE)
                     supported profiles (${PROFILES[@]})
   -v                verbose output
   -k                keep all the instances, skip deinit (default: $KEEP)
   -U                upgrade the node during restart (default: $UPGRADE)

[ACTIONS]
   launch            do launch only
   run               run benchmark
   log               download logs
   deinit            sync logs & terminate instances
   reset             reset dashboard and explorer
   dns               re-run dns setup
   bootnode          launch bootnode(s) only
   reinit <ip>       re-run init command on hosts (list of ips)
   multikey <ip>     start multi-bls-key migration
   restart <shard>   restart the shard or all if no <shard> is specified (default: all)
   all               do everything (default)


[EXAMPLES]

   $ME -p tiny
   $ME -p debug
   $ME -p devnet -k

   $ME -p testnet log

EOT
   exit 0
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
      -launch_profile launch-${PROFILE}.json
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
      -root_volume ${configs[leader.root]} \
      -protection=${configs[leader.protection]} \
      -launch_profile launch-${PROFILE}.json
      LAUNCH_OPT+=' -l raw_ip-leader.txt'
      num_leader=$(wc -l raw_ip-leader.txt)
      LEADER_IP=( $(cat raw_ip-leader.txt | awk ' { print $1 } ') )
   fi

   if [ ${configs[explorer_node.num_vm]} -gt 0 ]; then
      logging launching ${configs[explorer_node.num_vm]} explorer nodes: ${configs[explorer_node.type]}
      ../bin/instance \
      -config_dir $CONFIG_DIR \
      -instance_count ${configs[explorer_node.num_vm]} \
      -instance_type ${configs[explorer_node.type]} \
      -launch_region ${configs[explorer_node.regions]} \
      -aws_profile aws-explorer.json \
      -ip_file raw_ip-explorer_node.txt \
      -output instance_ids_output-explorer_node.txt \
      -tag_file instance_output-explorer_node.txt \
      -tag ${TAG}-explorer_node \
      -root_volume ${configs[explorer_node.root]} \
      -protection=${configs[explorer_node.protection]} \
      -launch_profile launch-${PROFILE}.json
      LAUNCH_OPT+=' -e raw_ip-explorer_node.txt'
      num_explorer_nodes=$(wc -l raw_ip-explorer_node.txt)
      EXPLORER_NODE_IP=( $(cat raw_ip-explorer_node.txt | awk ' { print $1 } ') )
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
      rm instance_ids_output-leader.txt instance_output-leader.txt &
   fi

   if [ ${configs[explorer_node.num_vm]} -gt 0 ]; then
      cat instance_ids_output-explorer_node.txt >> instance_ids_output.txt
      cat instance_output-explorer_node.txt >> instance_output.txt
      rm instance_ids_output-explorer_node.txt instance_output-explorer_node.txt &
   fi

   echo waiting for instances launch ${configs[flow.wait_for_launch]} ...
   sleep  ${configs[flow.wait_for_launch]}

   RETRY=8
   local r=0
   local prev_total=0

   local expected=$(wc -l raw_ip.txt | cut -f 1 -d ' ')
   while [ $r -le $RETRY ]; do
      local total=$(./aws-instances.sh -g $TAG | tail -n 1 | cut -f 1 -d ' ' 2>/dev/null)
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

function do_dns_setup
{
   R53=${THEPWD}/updater53.sh
   local NUM_RPC=${configs[flow.rpcnode]}
   if [[ -z "$NUM_RPC" || "$NUM_RPC" == "null" ]]; then
      NUM_RPC=5
   fi
   rm -f $R53

   [ ! -e $SESSION_FILE ] && errexit "can't find profile config file : $SESSION_FILE"
   TS=$(cat $SESSION_FILE | $JQ .sessionID)

   local n=0
   local shards=${configs[benchmark.shards]}

   while [ $n -lt $shards ]; do
# choose the top $NUM_RPC nodes as the rpc end points for state syncing
      local shard_file=${THEPWD}/logs/$TS/shard${n}.txt
      grep " $n " ${THEPWD}/logs/$TS/distribution_config.txt | cut -f1 -d' ' > $shard_file
      RPCS[$n]="$(head -n 1 $shard_file) "
      RPCS[$n]+=$(tail -n +2 $shard_file | sort -R | head -n ${NUM_RPC})

      echo python3 r53update.py ${configs[flow.rpczone]} $n ${RPCS[$n]} | tee -a $R53
      (( n++ ))
   done
   chmod +x $R53
   cp -f $R53 ${THEPWD}/logs/${TS}/

# execute the r53 command to set dns
   ${R53}

   echo wait for dns records update ... 60s
   sleep 60
}

function do_launch_bootnode
{
   BN=${1:-bootnode}
   if [ "${configs[${BN}.enable]}" != "true" ]; then
      echo "skipping launch bootnode: ${BN}"
      return
   fi

   local -a BOOTNODE_OPT
   logging launch $BN node - $PROFILE profile

   if [ -e $SESSION_FILE ]; then
      TS=$(cat $SESSION_FILE | $JQ .sessionID)
      BOOTNODE_OPT+=(-s "$TS")
   fi

   if [ -e ${CONFIG_DIR}/${configs[${BN}.p2pkey]} ]; then
      BOOTNODE_OPT+=(-K "${CONFIG_DIR}/${configs[${BN}.p2pkey]}")
   fi
   case "${configs[${BN}.log_conn]}" in
   ""|"null"|"false") ;;
   *) BOOTNODE_OPT+=(-L);;
   esac
   echo ./bootnode.sh -G -p ${configs[${BN}.port]} -f ${FOLDER} -S ${configs[${BN}.server]} -k ${configs[${BN}.key]} -P $PROFILE -n $BN "${BOOTNODE_OPT[@]}"
   ./bootnode.sh -G -p ${configs[${BN}.port]} -f ${FOLDER} -S ${configs[${BN}.server]} -k ${configs[${BN}.key]} -P $PROFILE -n $BN "${BOOTNODE_OPT[@]}"
   expense bootnode
   BN_MA+="$(cat ${BN}-ma.txt),"
}

function do_run
{
   logging run benchmark
   local RUN_OPTS=
   local -a NODE_OPTS

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
   local commit_delay="${configs[benchmark.commit_delay]:-}"
   case "${commit_delay}" in
   ""|"null") ;;
   *) NODE_OPTS+=(-d "${commit_delay}");;
   esac
   local log_conn="${configs[benchmark.log_conn]:-}"
   case "${log_conn}" in
   ""|"null"|"false") ;;
   *) NODE_OPTS+=(-L);;
   esac
   local network_type="${configs[benchmark.network_type]:-}"
   case "${network_type}" in
   ""|"null") ;;
   *) NODE_OPTS+=(-t "${network_type}");;
   esac
   local rpc_zone="${configs[flow.rpczone]}"
   case "${rpc_zone}" in
   null)
	   # not given in the config file; use node binary default
	   ;;
   *)
	   # given in the config file, including empty (which disables DNS)
	   NODE_OPTS+=(-z "${rpc_zone}.hmny.io")
	   ;;
   esac

   [ $VERBOSE ] && RUN_OPTS+=" -v"

   ./run_benchmark.sh -n ${configs[parallel]} ${RUN_OPTS} "${NODE_OPTS[@]}" -p $PROFILE -R init

   [ ! -e $SESSION_FILE ] && errexit "can't find profile config file : $SESSION_FILE"
   TS=$(cat $SESSION_FILE | $JQ .sessionID)

   # save the bootnode multiaddress
   [ -e bootnode-ma.txt ] && mv -f bootnode*-ma.txt logs/$TS

   expense run
}

function download_logs
{
   if [ -z $TS ]; then
      [ ! -e $SESSION_FILE ] && errexit "can't find profile config file : $SESSION_FILE"
      TS=$(cat $SESSION_FILE | $JQ .sessionID)
   fi

   logging download logs ...
   ./dl-soldier-logs.sh -p $PROFILE -g leader version

   if [ "${configs[logs.leader]}" == "true" ]; then
      ./dl-soldier-logs.sh -p $PROFILE -g leader benchmark
      ./dl-soldier-logs.sh -p $PROFILE -g validator soldier
   fi
   if [[ "${configs[logs.client]}" == "true" && ${configs[client.num_vm]} -gt 0 ]]; then
      ./dl-soldier-logs.sh -p $PROFILE -g client -D logs/$PROFILE/client.config.txt soldier
      ./dl-soldier-logs.sh -p $PROFILE -g client -D logs/$PROFILE/client.config.txt benchmark
   fi
   if [ "${configs[logs.validator]}" == "true" ]; then
      ./dl-soldier-logs.sh -p $PROFILE -g validator benchmark
   fi
   if [ "${configs[logs.soldier]}" == "true" ]; then
      ./dl-soldier-logs.sh -p $PROFILE -g leader soldier &
   fi
   if [ "${configs[logs.db]}" == "true" ]; then
      ./dl-soldier-logs.sh -p $PROFILE -g leader db &
      ./dl-soldier-logs.sh -p $PROFILE -g validator db &
   fi
   wait
   expense download
   rm -f logs/$PROFILE
   ln -sf $TS logs/$PROFILE

   cp -f $SESSION_FILE logs/$PROFILE
}

function analyze_logs
{
   if [ -z $TS ]; then
      [ ! -e $SESSION_FILE ] && errexit "can't find profile config file : $SESSION_FILE"
      TS=$(cat $SESSION_FILE | $JQ .sessionID)
   fi

   find logs/$TS/leader -name zerolog-validator-*.log > logs/$TS/all-leaders.txt
   find logs/$TS/validator -name zerolog-validator-*.log > logs/$TS/all-validators.txt
   logging analyzing logs in $(cat logs/$TS/all-leaders.txt)
   ${THEPWD}/cal_tps.sh logs/$TS/all-leaders.txt logs/$TS/all-validators.txt | tee ${THEPWD}/logs/$TS/tps.txt
   expense analysis
}

function do_sync_logs
{
   wait
   logging sync log to s3
   # optimize S3 log folder path such that all logs for the same day are stored in a signle folder
   YEAR=$(date +"%y")
   MONTH=$(date +"%m")
   DAY=$(date +"%d")
   TIME=$(date +"%T")
   TSDIR="$PROFILE/$YEAR/$MONTH/$DAY/$TIME"
   aws s3 sync logs/$TS s3://harmony-benchmark/logs/$TSDIR 2>&1 > /dev/null
   S3URL=s3://harmony-benchmark/logs/$TSDIR
   echo $S3URL
   echo "$TSDIR" | aws s3 cp - s3://harmony-benchmark/logs/latest-${WHOAMI}-${PROFILE}.txt
   expense s3_sync
}

function do_deinit
{
   if [ -z $TS ]; then
      [ ! -e $SESSION_FILE ] && errexit "can't find profile config file : $SESSION_FILE"
      TS=$(cat $SESSION_FILE | $JQ .sessionID)
   fi

   logging deinit ...
   if [ ${configs[azure.num_vm]} -gt 0 ]; then
      ../azure/go-az.sh deinit &
   fi

   ./aws-instances.sh -G delete
   rm -f *.ids

   wait
   expense deinit
   [ -e ${THEPWD}/logs/$TS/tps.txt ] && cat ${THEPWD}/logs/$TS/tps.txt
}

function do_reset_explorer
{
   explorer=${1:-explorer}

   [ ! -e $SESSION_FILE ] && errexit "can't find profile config file : $SESSION_FILE"
   TS=$(cat $SESSION_FILE | $JQ .sessionID)

   if [ "${configs[${explorer}.reset]}" == "true" ]; then
      host=$(host ${configs[${explorer}.name]} | awk ' { print $NF } ')
      KEY=$(find_key_from_ip $host)
      KEYDIR=${HSSH_KEY_DIR:-~/.ssh/keys}
      SCP="/usr/bin/scp -o StrictHostKeyChecking=no -o LogLevel=error -i $KEYDIR/$KEY"

      echo "resetting explorer ..."
      explorer_nodes=( $(grep explorer_node ${THEPWD}/logs/$TS/distribution_config.txt | cut -f1 -d" ") )
      for ex in ${explorer_nodes[@]}; do
         exp+="\"$ex\","
      done
      exp=$(echo $exp | sed s/,$//)
      cat > leaders.json<<EOT
[ $exp ]
EOT
      [ -e leaders.json ] && cp leaders.json logs/$TS
      ${SCP} logs/$TS/leaders.json ec2-user@${host}:projects/harmony-dashboard-backend/
   fi
}

reinit_ip() {
   local ip pfx f ok
   ip="${1}"
   ok=false
   for pfx in init leader.init explorer.init
   do
      f="logs/${TS}/init/${pfx}-${ip}.json"
      [ -f "${f}" ] || continue
      sed -i s/dns=false/dns=true/ ${f}
      ok=true
      echo curl -m 3 -X GET -s http://$ip:19000/init -H "Content-Type: application/json" -d@"${f}"
      curl -m 3 -X GET -s http://$ip:19000/init -H "Content-Type: application/json" -d@"${f}"
   done
   ${ok} || echo "WARNING: could not find init JSON file for ${ip}; skipped it" >&2
}

# re-run init command on some soldiers
function do_reinit
{
   soldiers=$*

   [ ! -e $SESSION_FILE ] && errexit "can't find profile config file : $SESSION_FILE"
   TS=$(cat $SESSION_FILE | $JQ .sessionID)

   if [ "$soldiers" == "all" ]; then
      pushd $logs/$TS/init
      declare -a IP
      IP=( $(find . -size 0 | sed 's/.*init.\(.*\).log/\1/' | awk -F. ' {print $1,$2,$3,$4} ' | tr ' ' . | tr '\n' ' ') )
      for ip in ${IP[@]}; do
         reinit_ip "${ip}"
      done
   else
      for s in $soldiers; do
         reinit_ip "${s}"
      done
   fi
}

# re-init a node with multi-key, pause other nodes
function do_multikey
{
   mkhost=$1
   shift

   [ ! -e $SESSION_FILE ] && errexit "can't find profile config file : $SESSION_FILE"
   TS=$(cat $SESSION_FILE | $JQ .sessionID)

   ./restart_node.sh -p $PROFILE -y -M $mkhost
}

function do_restart_network
{
   local shard=$1

   local logdir=logs/$PROFILE

   local restart_opt="-y -t 0 -r 0 -R 0"
   if $UPGRADE; then
      restart_opt+=" -U"
   fi

   logging restart network
   if [ -n "$shard" ]; then
      if [ ! -f $logdir/shard${shard}.txt ]; then
         echo "ERROR: can't find $logdir/shard${shard}.txt"
      else
         cat $logdir/shard${shard}.txt | xargs -P ${configs[parallel]} -I{} bash -c "./restart_node.sh -d $logdir -p $PROFILE $restart_opt {}"
      fi
   else
      # run on all shards
      for shard in $(seq 0 $(( ${configs[benchmark.shards]} - 1 ))); do
         if [ ! -f $logdir/shard${shard}.txt ]; then
            echo "ERROR: can't find $logdir/shard${shard}.txt"
         else
            (cat $logdir/shard${shard}.txt | xargs -P ${configs[parallel]} -I{} bash -c "./restart_node.sh -d $logdir -p $PROFILE $restart_opt {}") &
         fi
      done
   fi
   wait
   expense restart
}

function do_all
{
   do_launch_bootnode
   do_launch_bootnode bootnode1
   do_launch_bootnode bootnode3
   do_launch_bootnode bootnode4
   do_launch
   do_dns_setup
   do_run
   do_reset_explorer
   do_reset_explorer explorer2
   download_logs
   do_sync_logs
   do_restart_network
   if [ "$KEEP" == "false" ]; then
      do_deinit
   fi
   echo all logs are uploaded to
   echo $S3URL
}

######### VARIABLES #########
: ${WHOAMI="${USER}"}
export WHOAMI
PROFILE=tiny
PROFILES=( $(ls $CONFIG_DIR/benchmark-*.json | sed -e "s,$CONFIG_DIR/benchmark-,,g" -e 's/.json//g') )
SESSION_FILE=$CONFIG_DIR/profile-${PROFILE}.json
BENCHMARK_FILE=$CONFIG_DIR/benchmark-${PROFILE}.json
BUCKET=unique-bucket-bin
USERID=${WHOAMI}
FOLDER=$USERID
USERDATA=$CONFIG_DIR/userdata-soldier-http.sh
VERBOSE=
THEPWD=$(pwd)
KEEP=false
TAG=${WHOAMI}
UPGRADE=false

while getopts "hp:vkU" option; do
   case $option in
      h) usage ;;
      p)
         PROFILE=$OPTARG
         SESSION_FILE=$CONFIG_DIR/profile-${PROFILE}.json
         BENCHMARK_FILE=$CONFIG_DIR/benchmark-${PROFILE}.json
         [ ! -e $BENCHMARK_FILE ] && errexit "can't find benchmark config file : $BENCHMARK_FILE"
         ;;
      v) VERBOSE=1 ;;
      k) KEEP=true ;;
      U) UPGRADE=true ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$1
shift

if [ -z "$ACTION" ]; then
   ACTION=all
fi

read_profile $BENCHMARK_FILE
gen_userdata $BUCKET $FOLDER $USERDATA

case $ACTION in
   all)  
         do_all ;;
   bootnode)
      case "$1" in
         "")
            do_launch_bootnode
            do_launch_bootnode bootnode1
            do_launch_bootnode bootnode3
            do_launch_bootnode bootnode4
            ;;
         "bootnode1"|"bootnode2"|"bootnode3"|"bootnode4")
            do_launch_bootnode $1
            ;;
         *)
            echo "parameter has to be bootnode[1-4]"
            ;;
      esac
      ;;
   launch)
         do_launch ;;
   run)  
         do_launch_bootnode
         do_launch_bootnode bootnode1
         do_run ;;
   log)  
         download_logs
         do_sync_logs ;;
   deinit)
         do_deinit ;;
   reset)
         do_reset_explorer
         do_reset_explorer explorer2 ;;
   dns)
         do_dns_setup ;;
   reinit)
         do_reinit $* ;;
   multikey)
         do_multikey $* ;;
   restart)
         do_restart_network $* ;;
   *)
      echo "unknown action! \"$ACTION\""
      ;;
esac

exit 0
