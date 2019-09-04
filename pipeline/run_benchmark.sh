#!/usr/bin/env bash

#TODO: parameter validation

set -o pipefail
source ./common.sh || exit 1

function usage
{
   ME=$(basename $0)
   cat<<EOT
Usage: $ME [OPTIONS] ACTIONS

OPTIONS:
   -h                print this usage
   -f distribution   name of the distribution file (default: $DIST)
   -i ip_addresses   ip addresses of the soldiers to run command
                     delimited by ,
   -a application    name of the application to be updated
   -p profile        profile of the benchmark test (default: $PROFILE)
   -n num            parallel process num in a group (default: $PARALLEL)
   -v                verbose
   -D dashboard_ip   enable dashboard support, specify the ip address of
                     dashboard server (default: $DASHBOARD)
   -A attacked_mode  enable attacked mode support (default mode: $ATTACK)
   -C cross_ratio    enable cross_shard_ratio (default ratio: $CROSSTX)
   -N multiaddr      the multiaddress of the boot node (default: $BNMA)
   -P true/false     enable libp2p or not (default: $LIBP2P)
   -m minpeer        minimum number of peers required to start consensus
                     (default: $MINPEER)
   -c                invoke client node (default: $CLIENT)
   -d duration       when running validators tell them to delay commit messages
                     (default: use Harmony binary default)
   -z zone           use the given DNS zone; "" disables DNS-based discovery
                     (default: use Harmony binary default)
   -t network_type   use the given network type such as mainnet, testnet...
                     (default: use Harmony binary default)

ACTIONS:
   auto              automate the test execution based on test plan (TODO)
   ping              ping each soldier
   config            configure distribution_config to each soldier
   init              start benchmark test, after config
   kill              kill all running benchmark/txgen 
   update            update certain/all binaries on solider(s)
   wallet            start wallet on node

EXAMPLES:

   $ME -i 10.10.1.1,10.10.1,2 -a benchmark update
   $ME -f dist1.txt config
EOT
   exit 0
}

function read_session
{
   BUCKET=$($JQ .bucket $SESSION_FILE)
   FOLDER=$($JQ .folder $SESSION_FILE)
   SESSION=$($JQ .sessionID $SESSION_FILE)

   LOGDIR=${CACHE}logs/$SESSION

   mkdir -p $LOGDIR
}

function read_nodes
{
   read_session

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
   local start_index=0

   mkdir -p $LOGDIR/$cmd

   BOOTNODES="-bootnodes $BNMA"
   end=0
   group=0
   case $cmd in
      init)
      benchmarkArgs="$BOOTNODES -min_peers $MINPEER"
      if [ "${configs[benchmark.bls]}" == "true" ]; then
         benchmarkArgs+=" -blspass file:${configs[bls.pass]} -blskey_file BLSKEY"
      else
         benchmarkArgs+=" -account_index ACC_INDEX -is_genesis"
      fi
      case "${commit_delay+set}" in
      set)
         benchmarkArgs+=" -delay_commit=${commit_delay}"
         ;;
      esac
      if ${log_conn}
      then
         benchmarkArgs+=" -log_conn"
      fi
      case "${network_type+set}" in
      set)
         benchmarkArgs+=" -network_type=${network_type}"
         ;;
      esac
      txgenArgs="-duration -1 -cross_shard_ratio $CROSSTX $BOOTNODES"
      if [ -n "$DASHBOARD" ]; then
         benchmarkArgs+=" $DASHBOARD"
      fi
      # Disable DNS for the initial launch, only for bls enabled network
      # For older version like cello, we don't have -dns option support
      if [ "${configs[benchmark.bls]}" == "true" ]; then
         benchmarkArgs+=" -dns=false"
      fi
      if [ "$CLIENT" == "true" ]; then
         CLIENT_JSON=',"role":"client"'
      fi

      explorerArgs=$benchmarkArgs
      explorerArgs+=" -is_genesis=false -is_explorer=true -shard_id=SHARDID"
      cat>$LOGDIR/$cmd/leader.$cmd.json<<EOT
{
   "ip":"127.0.0.1",
   "port":"9000",
   "sessionID":"$SESSION",
   "benchmarkArgs":"${benchmarkArgs}",
   "txgenArgs":"$txgenArgs"
   $CLIENT_JSON
}
EOT
      cat>$LOGDIR/$cmd/$cmd.json<<EOT
{
   "ip":"127.0.0.1",
   "port":"9000",
   "sessionID":"$SESSION",
   "benchmarkArgs":"${benchmarkArgs}",
   "txgenArgs":"$txgenArgs"
   $CLIENT_JSON
}
EOT
      cat>$LOGDIR/$cmd/explorer.$cmd.json<<EOT
{
   "ip":"127.0.0.1",
   "port":"9000",
   "sessionID":"$SESSION",
   "benchmarkArgs":"${explorerArgs}",
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
      wallet)
### FIXME (leo) hardcode some wallet parameters here
            cat>$LOGDIR/$cmd/$cmd.json<<EOT
{
   "interval":"0.001",
   "number":"20",
   "loop":"2000",
   "shards":"2"
}
EOT
;;
   esac
 
   SECONDS=0

   WAIT_FOR_LEADER_LAUNCH=3
   CURL_TIMEOUT=20s

   cmd_file=$LOGDIR/run_init.sh
   echo "#!/usr/bin/env bash" > $cmd_file

# send commands to leaders at first
   for n in $(seq 1 ${configs[benchmark.shards]}); do
      local ip=${NODEIPS[$n]}
      CMD=$"curl -X GET -s http://$ip:1${PORT[$ip]}/$cmd -H \"Content-Type: application/json\""

      case $cmd in
         init|update|wallet)
            if [ "${configs[benchmark.bls]}" == "true" ]; then
               bls=${blskey[$start_index]}
               sed "s/BLSKEY/$bls/" $LOGDIR/$cmd/leader.$cmd.json > $LOGDIR/$cmd/leader.$cmd-$ip.json
               # download bls private key files to each leader
               ./node_ssh.sh -d $LOGDIR ec2-user@$ip "aws s3 cp s3://${configs[bls.bucket]}/${configs[bls.folder]}/$bls $bls"
            else
               local index=$(( ${configs[benchmark.peer_per_shard]} * ( $n - 1 ) ))
               sed "s/ACC_INDEX/$index/" $LOGDIR/$cmd/leader.$cmd.json > $LOGDIR/$cmd/leader.$cmd-$ip.json
            fi
            CMD+=$" -d@$LOGDIR/$cmd/leader.$cmd-$ip.json"
            (( start_index ++ ))
            ;;
      esac

      echo $n =\> $CMD
      echo "$TIMEOUT -s SIGINT ${CURL_TIMEOUT} $CMD > $LOGDIR/$cmd/$cmd.$ip.log" >> $cmd_file
   done

   if [ ${configs[explorer_node.num_vm]} -gt 0 ]; then
# send commands to explorers at second
      local explorer_shard_id=0
      local explorer_start_index=$((${configs[benchmark.shards]} + 1))
      local explorer_end_index=$((${configs[benchmark.shards]} * 2))
      for n in $(seq $explorer_start_index $explorer_end_index); do
         local ip=${NODEIPS[$n]}
         CMD=$"curl -X GET -s http://$ip:1${PORT[$ip]}/$cmd -H \"Content-Type: application/json\""

         case $cmd in
            init|update|wallet)
               sed "s/SHARDID/$explorer_shard_id/" $LOGDIR/$cmd/explorer.$cmd.json > $LOGDIR/$cmd/explorer.$cmd-$ip.json
               CMD+=$" -d@$LOGDIR/$cmd/explorer.$cmd-$ip.json"
               (( explorer_shard_id ++ ))
               ;;
         esac

         echo $n =\> $CMD
         echo "$TIMEOUT -s SIGINT ${CURL_TIMEOUT} $CMD > $LOGDIR/$cmd/$cmd.$ip.log" >> $cmd_file
      done
   fi

   local index=1
   while [ $end -lt $NUM_NODES ]; do
      start=$(( $PARALLEL * $group + ${configs[benchmark.shards]} * 2 + 1))
      end=$(( $PARALLEL + $start - 1 ))

      if [ $end -ge $NUM_NODES ]; then
         end=$NUM_NODES
      fi

      echo processing validators group: $group \($start to $end\)

      for n in $(seq $start $end); do
         local ip=${NODEIPS[$n]}
         CMD=$"curl -X GET -s http://$ip:1${PORT[$ip]}/$cmd -H \"Content-Type: application/json\""

         case $cmd in
            init|update|wallet)
               if [ "${configs[benchmark.bls]}" == "true" ]; then
                  bls=${blskey[$start_index]}
                  sed "s/BLSKEY/$bls/" $LOGDIR/$cmd/$cmd.json > $LOGDIR/$cmd/$cmd-$ip.json
                  # download bls private key files to each node
                  ./node_ssh.sh -d $LOGDIR ec2-user@$ip "aws s3 cp s3://${configs[bls.bucket]}/${configs[bls.folder]}/$bls $bls" &
               else
                  if [ $(( $index % ${configs[benchmark.peer_per_shard]} )) == 0 ]; then
                     (( index ++ ))
                  fi
                  sed "s/ACC_INDEX/$index/" $LOGDIR/$cmd/$cmd.json > $LOGDIR/$cmd/$cmd-$ip.json
                  (( index ++ ))
               fi

               CMD+=$" -d@$LOGDIR/$cmd/$cmd-$ip.json"
               (( start_index ++ ))
               ;;
         esac

         [ -n "$VERBOSE" ] && echo $n =\> $CMD
         echo "$TIMEOUT -s SIGINT ${CURL_TIMEOUT} $CMD > $LOGDIR/$cmd/$cmd.$ip.log &" >> $cmd_file
      done 
      wait
      echo "wait" >> $cmd_file
      (( group++ ))
   done

   # run the curl commands to init the harmony nodes
   # we only do it after the blskey file downloaded to each node
   chmod +x $cmd_file
   $cmd_file

   duration=$SECONDS

   succeeded=$(find $LOGDIR/$cmd -name $cmd.*.log -type f -exec grep Succeeded {} \; | wc -l)
   failed=$(( $NUM_NODES - $succeeded ))

   echo $(date): $cmd succeeded/$succeeded, failed/$failed nodes, $(($duration / 60)) minutes and $(($duration % 60)) seconds

   if [[ $failed -gt 0 && "${configs[benchmark.init_try]}" == "true" ]]; then
      echo "==== failed nodes, waiting for $WAIT_FOR_FAILED_NODES ===="
      find $LOGDIR/$cmd/\*.log -size 0 -exec basename {} \; | tee $LOGDIR/$cmd/failed.ips
      echo "==== retrying ===="
      IPs=$(cat $LOGDIR/$cmd/failed.ips | sed "s/$cmd.\(.*\).log/\1/")
      for ip in $IPs; do
         CMD=$"curl -X GET -s http://$ip:1${PORT[$ip]}/$cmd -H \"Content-Type: application/json\""

         case $cmd in
            init|update|wallet)
               CMD+=$" -d@$LOGDIR/$cmd/$cmd-$ip.json" ;;
         esac

         [ -n "$VERBOSE" ] && echo $n =\> $CMD
         $TIMEOUT -s SIGINT ${CURL_TIMEOUT} $CMD > $LOGDIR/$cmd/$cmd.$n.$ip.log &
      done
      wait

      succeeded=$(find $LOGDIR/$cmd -name $cmd.*.log -type f -exec grep Succeeded {} \; | wc -l)
      failed=$(( $NUM_NODES - $succeeded ))

      echo $(date): $cmd succeeded/$succeeded, failed/$failed nodes, $(($duration / 60)) minutes and $(($duration % 60)) seconds

   fi

   # add DNS zone option to init json for later restarts
   case "${cmd}" in
   init)
      case "${dns_zone+set}" in
      set)
         for initfile in \
            "${LOGDIR}/${cmd}/leader.${cmd}-"*".json" \
            "${LOGDIR}/${cmd}/${cmd}-"*".json"
         do
            : # $JQ '.benchmarkArgs += " -dns_zone='"${dns_zone}"'"' < "${initfile}" > "${initfile}.new"
            : # mv -f "${initfile}.new" "${initfile}"
         done
         ;;
      esac
      ;;
   esac
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
PROFILE=tiny
SESSION_FILE=$CONFIG_DIR/profile-${PROFILE}.json
BENCHMARK_FILE=$CONFIG_DIR/benchmark-${PROFILE}.json
DIST=distribution_config.txt
PARALLEL=100
VERBOSE=
DASHBOARD=
ATTACK=2
CROSSTX=30
MINPEER=10
CLIENT=
BNMA=
LIBP2P=false

declare -A NODES
declare -A NODEIPS
declare -A PORT

unset -v commit_delay log_conn dns_zone network_type
log_conn=false

#################### MAIN ####################
while getopts "hf:i:a:n:vD:A:C:m:cN:P:p:d:Lz:t:" option; do
   case $option in
      p)
         PROFILE=$OPTARG
         SESSION_FILE=$CONFIG_DIR/profile-${PROFILE}.json
         [ ! -e $SESSION_FILE ] && errexit "can't find session file : $SESSION_FILE"
         BENCHMARK_FILE=$CONFIG_DIR/benchmark-${PROFILE}.json
         [ ! -e $BENCHMARK_FILE ] && errexit "can't find benchmark config file : $BENCHMARK_FILE"
         ;;
      f) DIST=$OPTARG ;;
      i) IPS=$OPTARG ;;
      a) APP=$OPTARG ;;
      n) PARALLEL=$OPTARG ;;
      v) VERBOSE=true
         set -x ;;
      D) DASHBOARD="-metrics_report_url http://$OPTARG/report" ;;
      A) ATTACK=$OPTARG ;;
      C) CROSSTX=$OPTARG ;;
      m) MINPEER=$OPTARG ;;
      c) CLIENT=true ;;
      N) BNMA=$OPTARG ;;
      P) LIBP2P=$OPTARG ;;
      d) commit_delay="${OPTARG}";;
      L) log_conn=true;;
      z) dns_zone="${OPTARG}";;
      t) network_type="${OPTARG}";;
      h|?) usage ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$@

read_nodes
read_profile $BENCHMARK_FILE

case "$ACTION" in
   "ping"|"kill"|"init"|"update"|"wallet") do_simple_cmd $ACTION ;;
   "auto") do_auto ;;
   *) usage ;;
esac
