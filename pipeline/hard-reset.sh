#!/bin/bash

set -u

unset -v progname progdir
progname="${0##*/}"
case "${0}" in
*/*) progdir="${0%/*}";;
*) progdir=".";;
esac

SSH='ssh -o StrictHostKeyChecking=no -o LogLevel=error -o ConnectTimeout=5 -o GlobalKnownHostsFile=/dev/null'

. "${progdir}/msg.sh"
. "${progdir}/usage.sh"
. "${progdir}/util.sh"
. "${progdir}/common.sh"

print_usage() {
   cat <<- ENDEND

      usage: ${progname} -p <profile> [options] shard command

      options:
      -p          mandatory: profile of network to run on
                  (support only stn/os/ps/mkeys)

      -o outdir   use the given output directory
                  (default: the hard-reset/YYYY-MM-DDTHH:MM:SSZ subdir logs/profile)

      -y          say yes to cmd confirmation

      -w time     how long to wait before starting to fund accounts

      shard       the shard number, such as 0-3 ('all' means all shards)

      commands:

      reset       do the hard reset, one-click-do-everything
      soft_reset  do a soft reset

      prepare     do hard reset prepataion (collect log, validator info, pager duty maintainence window)
      check       do sanity check (consensus, version)

      network     do the network hard reset only
      explorer    reset explorer
      dashboard   reset staking dashboard
      watchdog    reset watchdog
      fund        do funding using fund.sh
      regression  start regression tests

      === not implemented yet ===
      sentry      reset/launch sentry nodes
            
ENDEND
}

######### variables #########
unset -v net_profile force_yes network dbprefix wait_time
force_yes=false
net_profile=
wait_time=10m
unset -v OPTIND OPTARG opt
OPTIND=1
while getopts :o:p:yw: opt
do
   case "${opt}" in
   '?') usage "unrecognized option -${OPTARG}";;
   ':') usage "missing argument for -${OPTARG}";;
   o) outdir="${OPTARG}";;
   p) net_profile="${OPTARG}"
      BENCHMARK_FILE="$CONFIG_DIR/benchmark-${net_profile}.json"
      [ ! -e "$BENCHMARK_FILE" ] && errexit "can't find benchmark config file : $BENCHMARK_FILE"
      ;;
   y) force_yes=true;;
   w) wait_time="${OPTARG}";;
   *) err 70 "unhandled option -${OPTARG}";;
   esac
done
shift $(( OPTIND - 1 ))

#### cmdline checking ####
case ${net_profile} in
   os|stn|pstn|mkeys)
      msg "profile: ${net_profile}"
      export HMY_PROFILE=${net_profile}
      ;;
   *) usage "invalid profile for hard-reset: ${net_profile}" ;;
esac

unset -v SHARD cmd
SHARD="${1-}"
shift 1 2> /dev/null || usage "missing shard argument"
case "$SHARD" in
   all|0|1|2|3) msg "shard: $SHARD" ;;
   *) usage "invalid shard number: $SHARD" ;;
esac

cmd="${1-}"
shift 1 2> /dev/null || usage "missing command argument"
case "${cmd}" in
   prepare|reset|network|soft_reset|explorer|dashboard|sentry|regression|watchdog|check|fund) msg "commmand: ${cmd}" ;;
   *) usage "invalid command: ${cmd}" ;;
esac

logdir="logs/${net_profile}"
if [ "${force_yes}" = false ] ;then
  printf "[Y]/n > "
  read -r yn
  if [ "${yn}" != "Y" ] ;then
     exit
  fi
fi

######### functions ###########
function hard_reset_shard
{
   local shard=$1
   msg "cat $logdir/shard${shard}.txt | xargs -i% -P50 bash -c \"./restart_node.sh -U -X -D -y -d logs/${net_profile} -p ${net_profile} -t 0 -r 0 -R 0 %\""
   cat "$logdir/shard${shard}.txt" | xargs -i% -P50 bash -c "./restart_node.sh -U -X -D -y -d logs/${net_profile} -p ${net_profile} -t 0 -r 0 -R 0 %"
}

function soft_reset_shard
{
   local shard=$1
   msg "cat $logdir/shard${shard}.txt | xargs -i% -P50 bash -c \"./restart_node.sh -y -d logs/${net_profile} -p ${net_profile} -t 0 -r 0 -R 0 %\""
   cat "$logdir/shard${shard}.txt" | xargs -i% -P50 bash -c "./restart_node.sh -y -d logs/${net_profile} -p ${net_profile} -t 0 -r 0 -R 0 %"
}

function check_consensus
{
   local shard=$1
   msg "./run_on_shard.sh -p ${net_profile} -T $shard 'sudo tac /home/tmp_log/*/zerolog*.log latest/zerolog*.log 2>/dev/null | grep -m 1 HOORAY'"

   if [ "${force_yes}" = true ] ;then
      option='-y'
   fi

   ./run_on_shard.sh -p "${net_profile}" -rST $option "$shard" 'sudo tac /home/tmp_log/*/zerolog*.log latest/zerolog*.log 2>/dev/null | grep -m 1 HOORAY'
}

function check_version
{
   local shard=$1
   msg "./run_on_shard.sh -p ${net_profile} -T $shard './harmony -version'"
   if [ "${force_yes}" = true ] ;then
      option='-y'
   fi

   ver=$(./run_on_shard.sh -p "${net_profile}" -rST $option "$shard" './harmony -version' 2>&1 | grep -oE 'version\s\S+\s' | sort -u)

   msg "**** FOUND: $ver"
}

function restart_watchdog
{
   msg "./restart_watchdog.sh -a restart -s $network"
   ./restart_watchdog.sh -a restart -s "$network"
}

function do_sanity_check
{
   local shard=$1
   if [ "$shard" = "all" ]; then
      # run on all shards
      for s in $(seq 0 $(( ${configs[benchmark.shards]} - 1 ))); do
         check_consensus "${s}"
         check_version "${s}"
      done
   else
      check_consensus "${shard}"
      check_version "${shard}"
   fi
}

function do_jenkins_release
{
   if [ ! -z "${JENKINS_CREDENTIALS}" ]; then
      local params="{'parameter': [{'name':'BRANCH', 'value':'master'}, {'name':'BRANCH_RELEASE', 'value':false}, {'name':'BUILD_TYPE', 'value':'release'}, {'name':'NETWORK', 'value':'${release}'}, {'name':'STATIC_BINARY', 'value':true}]}"
      curl -X POST https://jenkins.harmony.one/job/harmony-release/build?token=harmony-release \
         --user $JENKINS_CREDENTIALS \
         --data-urlencode json="${params}"
   fi
}

function restart_sentry
{
   msg "restart sentry"
#   KEYDIR=${HSSH_KEY_DIR:-~/.ssh/keys}
   for num in $(seq 1 "${configs[benchmark.shards]}"); do
      if [ "${configs[sentry${num}.enable]}" = "true" ]; then
         sentryip=${configs[sentry${num}.ip]}
         sentryshard=${configs[sentry${num}.shard]}
         sentryuser=${configs[sentry${num}.user]}
         msg "sentry${num}: $sentryuser@$sentryip/$sentryshard"
#         key=$(find_key_from_ip $sentryip)
# TODO: testing
#         echo ./node_ssh.sh ${sentryuser}@${sentryip} <<EOC
#         tmux new -s sentry -d || { tmux kill-session -t sentry && tmux new -s sentry -d; } ;
#         sleep 1 ;
#         tmux send-keys -t sentry "./auto_node.sh run --shard $sentryshard --auto-active --clean --network ${configs[benchmark.network_type]} --beacon-endpoint https://api.s0.${configs[flow.rpczone]}.hmny.io" Enter;
#EOC
      fi
   done
}

function restart_explorer
{
   msg "restart explorer backend"

   if [ "${force_yes}" = true ] ;then
      option='-y'
   fi

   firebase firestore:delete --all-collections --project "harmony-explorer-${net_profile}" $option
   $SSH "${configs[explorer.name]}" "nohup /home/ec2-user/projects/harmony-dashboard-backend/restart_be.sh 1>/dev/null 2>/dev/null &"
}

function restart_dashboard
{
   msg "clear dashboard db"
   if [ "${force_yes}" = true ] ;then
      option='-y'
   fi

   for collection in global history; do
      firebase firestore:delete --project staking-explorer -r "${dbprefix}_${collection}" $option
   done
}

function start_regression_tests
{
   if [ ! -z "${JENKINS_CREDENTIALS}" ]; then
      msg "starting regression tests"
      local params="{'parameter': [{'name':'Network', 'value':'${net_profile^^}'}, {'name':'Run', 'value':'All tests'}]}"
      curl -X POST https://jenkins.harmony.one/job/regression_test/build?token=regression_test \
         --user $JENKINS_CREDENTIALS \
         --data-urlencode json="${params}"
   fi
}

function do_capture_validator_info
{
   EP="https://api.s0.${net_profile}.hmny.io/"
   msg "capturing all validator info"

   curl --location --request POST "$EP" \
   --header 'Content-Type: application/json' \
   --header 'Content-Type: text/plain' \
   --data-raw '{
          "jsonrpc":"2.0",
          "method":"hmy_getAllValidatorInformation",
          "params":[0],
          "id":1
   }' | jq . > "$logdir/all-validator-info.json"
}

function do_pagerduty_maintenance
{
   if [ ! -e ~/bin/pagerduty_token.sh ]; then
      msg "ERR: can't find the pagerduty token."
      return
   fi
   . ~/bin/pagerduty_token.sh

   local id="${PDS[$network]}"

   datafile="${logdir}/$(mktemp pd.XXXXXX.json)"
   now=$(date --rfc-3339=sec | tr " " T)
   # default maintenance window is 1 hour
   end=$(date -d "+1 hour" --rfc-3339=sec | tr " " T)

   cat>"$datafile"<<-EOT
{
   "maintenance_window": {
      "start_time": "$now",
      "end_time": "$end",
      "description": "$network hard reset maintenance_window",
      "type": "maintenance_window",
      "services": [
         { "id": "$id",
           "type": "service_reference"
         }
      ]
   }
}
EOT
   curl --request POST \
     --url https://api.pagerduty.com/maintenance_windows \
     --header 'accept: application/vnd.pagerduty+json;version=2' \
     --header 'authorization: Token token='"${PDTOKEN}" \
     --header 'content-type: application/json' \
     --header 'from: pagerduty@harmony.one' \
     --data @"${datafile}"

   rm -f "${datafile}"
}

function do_preparation
{
   do_capture_validator_info

   msg "backup logs and clean up logs"
   ./go.sh -p "$net_profile" log
   rm -rf "${logdir}/validator" "${logdir}/leader" "${logdir}/run_on_shard/*"

   do_pagerduty_maintenance
}

function _clean_rclone_snapshot
{
   case "$net_profile" in
      "os")
         msg "cleaning harmony_db_0 rclone snapshot, only for ostn"
         aws s3 rm s3://pub.harmony.one/ostn/harmony_db_0/
         # clean and stop ostn nodes setup for rclone snapshot
         popd "$progdir/../ansible"
         ansible-playbook playbooks/cleanup.yml -i inventory/ostn.ankr.yml -e 'user=root inventory=ostnexp'
         popd
         ;;
      *) msg "rclone snapshot for ostn only, skipping" ;;
   esac
}

function _do_hard_reset_once
{
   _clean_rclone_snapshot

   msg 'restart watchdog'
   restart_watchdog

   # FIXME: this script can only be run on devop machine using ec2-user account
   # the faucet_deploy.sh won't push to public repo
   #pushd ~/CF
   echo ./faucet_deploy.sh "${net_profile}"
   #popd
}

function _do_reset_network
{
   local shard=$1

   msg "restart bootnodes"
   ./go.sh -p "${net_profile}" bootnode

   if [ "$shard" = "all" ]; then
      # run on all shards
      for shard in $(seq 0 $(( ${configs[benchmark.shards]} - 1 ))); do
         if [ ! -f "$logdir/shard${shard}.txt" ]; then
            msg "ERR: can't find $logdir/shard${shard}.txt"
         else
            msg "do hard reset of all shards in $net_profile"
            hard_reset_shard "${shard}" &
         fi
      done
   else
      if [ ! -f "$logdir/shard${shard}.txt" ]; then
         msg "ERR: can't find $logdir/shard${shard}.txt"
      else
         msg "do hard reset of shard ${shard} in $net_profile"
         hard_reset_shard "${shard}"
      fi
   fi

   wait
   _do_hard_reset_once
}

function do_soft_reset_network
{
   local shard=$1

   if [ "$shard" = "all" ]; then
      # run on all shards
      for shard in $(seq 0 $(( ${configs[benchmark.shards]} - 1 ))); do
         if [ ! -f "$logdir/shard${shard}.txt" ]; then
            msg "ERR: can't find $logdir/shard${shard}.txt"
         else
            msg "do softr reset of all shards in $net_profile"
            soft_reset_shard "${shard}" &
         fi
      done
   else
      if [ ! -f "$logdir/shard${shard}.txt" ]; then
         msg "ERR: can't find $logdir/shard${shard}.txt"
      else
         msg "do soft reset of shard ${shard} in $net_profile"
         soft_reset_shard "${shard}"
      fi
   fi

   wait
}

function do_reset
{
   do_preparation
   _do_reset_network "$SHARD"
   do_sanity_check "$SHARD"

   restart_explorer
   restart_dashboard

   msg "do funding and faucet. waiting for ${wait_time} ..."
   # FIXME: when to do the funding and not breaking consensus. 10m is 2 epoch.
   sleep $wait_time

   do_funding
   # do_jenkins_release # disable for now - needs more testing
   restart_sentry
}

function do_funding
{  
   # Make sure that extra STN testing accounts (e.g. the Jenkins regression test account etc) are funded
   if [ "${net_profile,,}" = "stn" ]; then
      ./fund.sh -f -c -s 0,1 -u "https://docs.google.com/spreadsheets/d/e/2PACX-1vRPu3s3EGI4v1LJBsME26FJifnS9MwYzTNujOoGnKq8M5YmQ6bxoHaKEAIx5RVBVniHTcZxLMvg9WW-/pub?gid=0&single=true&output=csv"
   fi
   
   ./fund.sh -f -c
}

function check_env
{
   # check firebase installation
   if ! which firebase > /dev/null; then
      msg "please install firebase on your host"
      return 1
   fi

   # check firebase project access: staking explorer
   if ! firebase projects:list | grep staking-explorer; then
      msg "you don't have access to firebase staking dashboard"
      msg "try 'firebase login --no-localhost'"
      return 1
   fi

   # check firebase project access: harmony explorer
   if ! firebase projects:list | grep harmony-explorer; then
      msg "you don't have access to firebase harmony explorer"
      msg "try 'firebase login --no-localhost'"
      return 1
   fi

   if ! which gcloud; then
      msg "gcloud command is not found"
      msg "install from https://cloud.google.com/sdk/gcloud/"
      return 1
   fi
   if ! gcloud auth list | grep ACTIVE 2>/dev/null; then
      msg "gcloud account is not configured"
      msg "please run 'gcloud init' and 'gcloud auth login'"
      return 1
   fi

   return 0
}

######### main ###########
case $net_profile in
   os) network=ostn
       dbprefix=Openstakingnet
       release=pangaea;;
   stn) network=stn
       dbprefix=stressnet
       release=stressnet;;
   ps) network=pstn
       dbprefix=partnernet
       release=partner;;
   mkeys)
       network=mkeys;;
       # TO-DO: dbprefix is unknown for mkeys atm, will add it later if needed 
   *) msg "ERR: unknown network profile for hard-reset: $net_profile, skipping"
      exit 1
esac

read_profile "$BENCHMARK_FILE"
if ! check_env; then
   err 90 "ERR: environment setup checking failed"
fi

case "${outdir+set}" in
'')
   mkdir -p "${logdir}/hard_reset"
   outdir="$(mktemp -d "${logdir}/hard_reset/$(date -u +%Y-%m-%dT%H:%M:%SZ).XXXXXX")"
   msg "using outdir ${outdir}"
   ;;
esac
mkdir -p "${outdir}"

case "${cmd}" in
   "reset")
      do_reset ;;
   "prepare")
      do_preparation ;;
   "check")
      do_sanity_check "$SHARD" ;;
   "network")
      _do_reset_network "$SHARD" ;;
   "soft_reset")
      do_soft_reset_network "$SHARD" ;;
   "fund")
     do_funding ;;
   "explorer")
      restart_explorer ;;
   "dashboard") 
      restart_dashboard ;;
   "watchdog")
      restart_watchdog ;;
   "sentry")
      restart_sentry ;;
   "regression")
      start_regression_tests ;;
   *)
      print_usage ;;
esac

# vim: set expandtab:ts=3
