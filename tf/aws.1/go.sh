#!/usr/bin/env bash
# this script is used to launch Harmony validatro nodes using terraform recipe

source ./regions.sh
ME=`basename $0`

set -o pipefail
set -x

if [ "$(uname -s)" == "Darwin" ]; then
   TIMEOUT=gtimeout
else
   TIMEOUT=timeout
fi

if [[ -e "$WHOAMI" || "$WHOAMI" == "ec2-user" ]]; then
   echo WHOAMI is not set or set to ec2-user
   exit 0
fi

if [ -e "$HMY_PROFILE" ]; then
   echo HMY_PROFILE is not set
   exit 0
fi

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

# expense has to be called after logging
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

STATEDIR=states

function usage
{
   cat<<EOF
Usage: $ME [Options] Command
This script will be used manage terraform nodes: launch new , replace existing.

PREREQUISITE:
 * this script can only be run on devop.hmny.io host
 * make sure you have [mainnet] section in ~/.aws/credentials
 * set WHOAMI environment variable (export WHOAMI=???)
 * set HMY_PROFILE environment variable (export HMY_PROFILE=???)
 * terraform state file directory, using sync_state.sh to upload/download the terraform.tfstate files
 * log directory of all init*.json files, default to logs/\$HMY_PROFILE

OPTIONS:
   -h                         print this help message
   -n                         dry run mode
   -v                         verbose mode
   -G                         do the real job
   -s state-file-directory    specify the directory of the terraform state files (default: $STATEDIR)
   -d log-file-directory      specify the directory of the log directory (default: logs/$HMY_PROFILE)

COMMANDS:
   replace [list of ip]       list of IP addresses of the existing node to be replaced, delimited by space
   new [list of index]        list of index of the harmony node in internal/genesis/harmony.go, delimited by space
   fast [list of ip]          list of IP addresses to do fast state syncing using snapshot, delimited by space

EXAMPLES:

   $ME -v

   $ME new 20 30 5

   $ME replace 12.34.56.78 123.234.123.234

   $ME fast 12.34.56.78 123.234.123.234

EOF
   exit 0
}

LOGDIR=logs/$HMY_PROFILE
DRYRUN=echo
OUTPUT=$LOGDIR/$(date +%F.%H:%M:%S).log

while getopts "hnvGss:d:" option; do
   case $option in
      n) DRYRUN=echo [DRYRUN] ;;
      v) VERBOSE=-v ;;
      G) DRYRUN= ;;
      s) STATEDIR=$OPTARG ;;
      d) LOGDIR=$OPTARG ;;
      h|?|*) usage ;;
   esac
done

shift $(($OPTIND-1))

CMD="$1"
shift

if [ "$CMD" = "" ]; then
   usage
fi

if [ ! -d $STATEDIR ]; then
   echo invalid state directory: $STATEDIR
   exit 0
fi

if [ ! -d $LOGDIR ]; then
   echo invalid log directory: $LOGDIR
   exit 0
fi

# launch one terraform node based on index
function _do_launch_one {
   local index=$1

   if [ -z $index ]; then
      echo no index, exit
      return
   fi
   if [[ $index -le 0 || $index -ge 680 ]]; then
      echo index: $index is out of bound
      return
   fi

   region=${REGIONS[$RANDOM % ${#REGIONS[@]}]}
   terraform apply -var "aws_region=$region" -var "blskey_index=$index" -auto-approve || return
   IP=$(terraform output | jq -rc '.public_ip.value  | @tsv')
   echo "$IP" >> $OUTPUT
   sleep 1
   mv -f terraform.tfstate states/terraform.tfstate.$index
}

function do_state_sync
{
   aws --profile mainnet s3 sync states/ s3://mainnet.log/states/
}

function new_instance
{
   indexes=$@
   for i in $indexes; do
      _do_launch_one $i
   done

   do_state_sync
}

# find index number based on the state file
function _find_index_from_state
{
   ip=$1
   index=$(grep -l $ip $STATEDIR | awk -F. ' { print $3 } ')
   echo $index
}

# find index number based on the init file
function _find_index_from_init
{
   ip=$1
   file=$(ls $LOGDIR/init/*init-$ip.json)
   if [ -f "$file" ]; then
      key=$(grep -oE 'blskey_file .*.key' $file | awk ' { print $2 } ' | sed 's/.key//')
      if [ -n "$key" ]; thebn
         index=$(grep $key variables.tf | awk ' { print $1 } ' | tr -d \")
         echo $index
      fi
   fi
}

# replace existing instance
function replace_instance
{
   ips=$@
   for ip in $ips; do
      index=$(_find_index_from_state $ip)
      if [ -z "$index" ]; then
         index=$(_find_index_from_init $ip)
      fi
      if [ -n "$index" ]; then
         _do_launch_one $index
      fi
   done
   do_state_sync
}

# do fast state syncing using the db snapshot
function fast_sync
{
   ips=$@
   for ip in $ips; do
      ssh ec2-user@$ip 'nohup /home/ec2-user/fast.sh > fast.log 2> fast.err < /dev/null &'
   done
}

###############################################################################
case $CMD in
   *) usage ;;
   new) new_instance $@ ;;
   replace) replace_instance $@ ;;
   fast) fast_sync $@ ;;
esac
