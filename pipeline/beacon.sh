#!/bin/bash
# this script is used to launch/terminate beacon node on Jenkins server
# it can download beacon binary from s3 bucket, and kill existing beacon process
# and launch new beacon process.  All done remotely on Jenkins server
# You should have keys to access Jenkins server

set -euo pipefail
# IFS=$'\n\t'

ME=`basename $0`
NOW=$(date +%Y%m%d.%H%M%S)
SSH='/usr/bin/ssh -o StrictHostKeyChecking=no -o LogLevel=error -i ../keys/california-key-benchmark.pem'
JENKINS=jenkins.harmony.one

function usage
{
   cat<<EOF
Usage: $ME [Options] Command
This script is used to launch/terminate beacon node on Jenkins server.

OPTIONS:
   -h             print this help message
   -v             verbose mode
   -G             do the real job (dryrun by default)
   -p port        port number of the beacon node (default: $PORT)
   -s shard       number of shards (default: $SHARD)
   -b bucket      the bucket name in the s3 (default: $BUCKET)
   -f folder      the folder name in the bucket (default: $FOLDER)

COMMANDS:
   download       download beacon binary
   kill           kill running beacon node process
   launch         launch new beacon node process
   all            do all the above 3 actions (default)

EOF
   exit 0
}

function _do_download
{
   local URL="https://$BUCKET.s3.amazonaws.com/$FOLDER/beacon"

   $DRYRUN ${SSH} ec2-user@${JENKINS} "mkdir -p $WORKDIR; pushd $WORKDIR; curl -O $URL; chmod +x beacon; ./beacon -version"
}

function _do_kill
{
   local pids=$(${SSH} ec2-user@${JENKINS} "ps -ef | grep beacon | grep -v grep | grep $PORT | awk ' { print \$2 } ' | tr '\n' ' '")

   if [ -n "$pids" ]; then
      $DRYRUN ${SSH} ec2-user@${JENKINS} "sudo kill -9 $pids"
   else
      echo "no beacon process to kill"
   fi
}

function _do_launch
{
   local cmd="pushd $WORKDIR; nohup sudo ./beacon -ip 0.0.0.0 -port $PORT -numShards $SHARD"
   $DRYRUN ${SSH} ec2-user@${JENKINS} "$cmd > run-beacon.log 2>&1 &"
}

function _do_all
{
   _do_download
   _do_kill
   _do_launch
}

#####################################################################

DRYRUN=echo
PORT=9999
SHARD=2
BUCKET=unique-bucket-bin
USERID=${WHOAMI:-$USER}
FOLDER=$USERID

while getopts "hvGp:s:b:f:" option; do
   case $option in
      v) VERBOSE=-v ;;
      G) DRYRUN= ;;
      p) PORT=$OPTARG ;;
      s) SHARD=$OPTARG ;;
      b) BUCKET=$OPTARG ;;
      f) FOLDER=$OPTARG ;;
      h|?|*) usage ;;
   esac
done

shift $(($OPTIND-1))

CMD="$@"

if [ "$CMD" = "" ]; then
   CMD=all
fi

WORKDIR=beacon-$FOLDER-$NOW

case $CMD in
   download) _do_download ;;
   kill) _do_kill ;;
   launch) _do_launch ;;
   all) _do_all ;;
   *) usage ;;
esac

if [ ! -z $DRYRUN ]; then
   echo '***********************************'
   echo "Please use -G to do the real work"
   echo '***********************************'
fi
