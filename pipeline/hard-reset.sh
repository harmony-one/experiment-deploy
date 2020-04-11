#!/bin/sh

set -eu

unset -v progname progdir
progname="${0##*/}"
case "${0}" in
*/*) progdir="${0%/*}";;
*) progdir=".";;
esac

. "${progdir}/msg.sh"
. "${progdir}/usage.sh"
. "${progdir}/util.sh"
. "${progdir}/common.sh"

print_usage() {
   cat <<- ENDEND

      usage: ${progname} -p <profile> [options] shard command

      options:
      -p          mandatory: profile of network to run on (example: stn)

      -o outdir   use the given output directory
                  (default: the hard-reset/YYYY-MM-DDTHH:MM:SSZ subdir logs/profile)

      -T          terse output; do not use BEGIN/END preamble for stdout/stderr
                  (useful for one-liners)

      -y          say yes to cmd confirmation

      shard       the shard number, such as 0-3 ('all' means all shards)

      commands:

      reset       do the hard reset, everything

      network     do the network hard reset only
      explorer    reset explorer
      dashboard   reset staking dashboard
      sentry      reset/launch sentry nodes
      regression  start regression test
            
ENDEND
}

######### variables #########
unset -v terse net_profile force_yes
terse=false
force_yes=false
net_profile=
unset -v OPTIND OPTARG opt
OPTIND=1
while getopts :o:Tp:y opt
do
   case "${opt}" in
   '?') usage "unrecognized option -${OPTARG}";;
   ':') usage "missing argument for -${OPTARG}";;
   o) outdir="${OPTARG}";;
   T) terse=true;;
   p) net_profile="${OPTARG}"
      BENCHMARK_FILE=$CONFIG_DIR/benchmark-${net_profile}.json
      [ ! -e $BENCHMARK_FILE ] && errexit "can't find benchmark config file : $BENCHMARK_FILE"
      export HMY_PROFILE=${net_profile}
      ;;
   y) force_yes=true;;
   *) err 70 "unhandled option -${OPTARG}";;
   esac
done
shift $((${OPTIND} - 1))

#### cmdline checking ####1
unset -v shard cmd
shard="${1-}"
shift 1 2> /dev/null || usage "missing shard argument"
cmd="${1-}"
shift 1 2> /dev/null || usage "missing command argument"

if [ -z "${net_profile}" ] ;then
   msg "profile not set, exiting..."
   msg "please use -p option to specify profile"
   exit 1
fi
logdir="logs/${net_profile}"
msg "profile: ${net_profile}"
msg "execute: ${cmd}"
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
   shard=$1
   msg "cat $logdir/shard${shard}.txt | xargs -i{} -P50 bash -c \"./restart_node.sh -U -X -D -y -d logs/${net_profile} -p ${net_profile} -t 0 -r 0 -R 0 {}\""
}

function check_consensus
{
   shard=$1
   msg "./run_on_shard.sh -p ${net_profile} -T $shard 'tac /home/tmp_log/*/zeorlog*.log | grep -m 1 HOORAY'"
}

function check_version
{
   shard=$1
   msg "./run_on_shard.sh -p ${net_profile} -T $shard './harmony -version'"
}

function restart_watchdog
{
   NET=$(echo $net_profile | tr [a-z] [A-Z])
   msg "./update_watchdog.sh -w $NET -t $net_profile -u -p -r -y"
   ./update_watchdog.sh -w $NET -t $net_profile -u -p -r -y
}

function _do_hard_reset_per_shard
{
   shard=$1
   hard_reset_shard ${shard}
   check_consensus ${shard}
   check_version ${shard}
}

function do_jenkins_release
{
   msg 'TODO: curl jenkins command'
   msg 'ex: https://jenkins.harmony.one/job/harmony-release/413/api/json'
}

function restart_sentry
{
   msg "restart sentry"
#   KEYDIR=${HSSH_KEY_DIR:-~/.ssh/keys}
   for num in $(seq 1 ${configs[benchmark.shards]}); do
      if [ "${configs[sentry${num}.enable]}" == "true" ]; then
         sentryip=${configs[sentry${num}.ip]}
         sentryshard=${configs[sentry${num}.shard]}
         sentryuser=${configs[sentry${num}.user]}
         msg "sentry${num}: $sentryuser@$sentryip/$sentryshard"
#         key=$(find_key_from_ip $sentryip)
# TODO: testing
         echo ./node_ssh.sh ${sentryuser}@${sentryip} <<EOC
         tmux new -s sentry -d || { tmux kill-session -t sentry && tmux new -s sentry -d; } ;
         sleep 1 ;
         tmux send-keys -t sentry "./auto_node.sh run --shard $sentryshard --auto-active --clean --network ${configs[benchmark.network_type]} --beacon-endpoint https://api.s0.${configs[flow.rpczone]}.hmny.io" Enter;
EOC
      fi
   done
}

function restart_explorer
{
   msg "restart explorer backend"
   explorerip=$(host ${configs[explorer.name]} | awk ' { print $NF } ')
# TODO: testing
   echo ./node_ssh.sh ${explorerip} <<EOC
      tmux new -s explorerbe -d || { tmux kill-session -t explorerbe && tmux new -s explorerbe -d; } ;
      sleep 1 ;
      tmux send-keys -t explorerbe "npm run db-reset; sleep 3; npm run start" Enter;
EOC
      fi
}

function restart_dashboard
{
   msg "clear dashboard db"
   dashboardip=$(host ${configs[dashboard.name]} | awk ' { print $NF } ')
# TODO: testing
   echo ./node_ssh.sh ${dashboardip} <<EOC
      tmux new -s dashboardbe -d || { tmux kill-session -t dashboardbe && tmux new -s dashboardbe -d; } ;
      sleep 1 ;
      tmux send-keys -t dashboardbe "cd appengine && npm install" Enter;
EOC
      fi
}

function start_regresssion
{
   msg "start regression test async using Jenkins"
   msg "TODO: @seb"
}

function _do_hard_reset_once
{
   msg 'restart watchdog'
   restart_watchdog

   msg 'do funding and faucet'
   ./fund.sh -f -c

   # FIXME: this script can only be run on devop machine using ec2-user account
   # the faucet_deploy.sh won't push to public repo
   pushd ~/CF
   echo ./faucet_deploy.sh ${net_profile}
   popd
}

function _do_reset_network
{
   if [ "$shard" == "all" ]; then
      # run on all shards
      for shard in $(seq 0 $(( ${configs[benchmark.shards]} - 1 ))); do
         if [ ! -f $logdir/shard${shard}.txt ]; then
            msg "ERR: can't find $logdir/shard${shard}.txt"
         else
            msg "do hard reset of all shards in $net_profile"
            _do_hard_reset_per_shard ${shard}
         fi
      done
   else
      if [ ! -f $logdir/shard${shard}.txt ]; then
         msg "ERR: can't find $logdir/shard${shard}.txt"
      else
         msg "do hard reset of shard ${shard} in $net_profile"
         _do_hard_reset_per_shard ${shard}
      fi
   fi
   _do_hard_reset_once
}

function do_reset
{
   _do_reset_network
   do_jenkins_release
   restart_sentry
}

function check_env
{
   # check firebase installation
   if ! which firebase > /dev/null; then
      msg "please install firebase on your host"
      return false
   fi

   # check firebase project access: staking explorer
   if ! firebase projects:list | grep staking-explorer; then
      msg "you don't have access to firebase staking dashboard"
      msg "try 'firebase login --no-localhost'"
      return false
   fi

   # check firebase project access: harmony explorer
   if ! firebase projects:list | grep harmony-explorer; then
      msg "you don't have access to firebase harmony explorer"
      msg "try 'firebase login --no-localhost'"
      return false
   fi

   return true
}

######### main ###########
read_profile $BENCHMARK_FILE
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
   "network")
      _do_reset_network ;;
   "explorer")
      restart_explorer ;;
   "dashboard") 
      restart_dashboard ;;
   "watchdog")
      restart_watchdog ;;
   "sentry")
      restart_sentry ;;
   "regression")
      start_regression ;;
   *)
      print_usage ;;
esac
