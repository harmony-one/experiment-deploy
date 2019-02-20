#!/bin/bash
# this script is used to launch/terminate bootnode node on Jenkins server
# it can download bootnode binary from s3 bucket, and kill existing bootnode process
# and launch new bootnode process.  All done remotely on Jenkins server
# You should have keys to access Jenkins server
# TODO: we should launch multiple bootnodes. We need to test multiple bootnodes and the p2p network.

set -euo pipefail
# IFS=$'\n\t'

ME=`basename $0`
NOW=$(date +%Y%m%d.%H%M%S)
SSH='/usr/bin/ssh -o StrictHostKeyChecking=no -o LogLevel=error -i ../keys/california-key-benchmark.pem'
SCP='/usr/bin/scp -o StrictHostKeyChecking=no -o LogLevel=error -i ../keys/california-key-benchmark.pem'
JENKINS=jenkins.harmony.one

function usage
{
   cat<<EOF
Usage: $ME [Options] Command
This script is used to launch/terminate bootnode program on Jenkins server.

OPTIONS:
   -h             print this help message
   -v             verbose mode
   -G             do the real job (dryrun by default)
   -p port        port number of the bootnode (default: $PORT)
   -b bucket      the bucket name in the s3 (default: $BUCKET)
   -f folder      the folder name in the bucket (default: $FOLDER)
   -S server      the server used to launch bootnode (default: $SERVER)

COMMANDS:
   download       download bootnode binary
   kill           kill running bootnode node process
   launch         launch new bootnode node process
   all            do all the above 3 actions (default)

EOF
   exit 0
}

function _do_download
{
   FILES=( bootnode libbls384.so libmcl.so )
	FN=go-bootnode-$PORT.sh

   echo "#!/bin/bash" > $FN
   for file in "${FILES[@]}"; do
      echo "curl -O https://$BUCKET.s3.amazonaws.com/$FOLDER/$file" >> $FN
   done
   echo "chmod +x bootnode" >> $FN
   echo "LD_LIBRARY_PATH=. ./bootnode -version" >> $FN
	chmod +x $FN

   echo ${SSH} ec2-user@${SERVER}
   $DRYRUN ${SSH} ec2-user@${SERVER} "mkdir -p $WORKDIR; pushd $WORKDIR"
   $DRYRUN ${SCP} $FN ec2-user@${SERVER}:$WORKDIR
   $DRYRUN ${SSH} ec2-user@${SERVER} "pushd $WORKDIR; ./$FN"
   echo "bootnode workdir: $WORKDIR"
}

function _do_kill
{
   local pids=$(${SSH} ec2-user@${SERVER} "ps -ef | grep bootnode | grep $PORT | grep -v grep | grep -v bootnode.sh | awk ' { print \$2 } ' | tr '\n' ' '")

   if [ -n "$pids" ]; then
      $DRYRUN ${SSH} ec2-user@${SERVER} "sudo kill -9 $pids"
      echo "bootnode node killed $pids"
   else
      echo "no bootnode process to kill"
   fi
}

function _do_launch
{
   local cmd="pushd $WORKDIR; nohup sudo LD_LIBRARY_PATH=. ./bootnode -ip 54.183.5.66 -port $PORT -key bootnode-$PORT.key"
   $DRYRUN ${SSH} ec2-user@${SERVER} "$cmd > run-bootnode.log 2>&1 &"
   echo "bootnode node started, sleeping for 5s ..."
   sleep 5
}

function _do_get_multiaddr
{
   local cmd="pushd $WORKDIR >/dev/null; grep 'BN_MA' run-bootnode.log | awk -F\= ' { print \$2 } ' | tr '\n' ' ' | tr -d ' ' "
   MA=$($DRYRUN ${SSH} ec2-user@${SERVER} $cmd)
   echo $MA | tee bn-ma.txt
}

function _do_all
{
   _do_download
   _do_kill
   _do_launch
   _do_get_multiaddr
}

#####################################################################

DRYRUN=echo
PORT=9876
BUCKET=unique-bucket-bin
USERID=${WHOAMI:-$USER}
FOLDER=$USERID
SERVER=${JENKINS}

while getopts "hvGp:b:f:S:" option; do
   case $option in
      v) VERBOSE=-v ;;
      G) DRYRUN= ;;
      p) PORT=$OPTARG ;;
      b) BUCKET=$OPTARG ;;
      f) FOLDER=$OPTARG ;;
      S) SERVER=$OPTARG ;;
      h|?|*) usage ;;
   esac
done

shift $(($OPTIND-1))

CMD="$@"

if [ "$CMD" = "" ]; then
   CMD=all
fi

WORKDIR=bootnode-$FOLDER-$NOW

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
