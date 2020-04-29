#!/bin/bash
# this script is used to launch/terminate bootnode node on bootnode server
# it can download bootnode binary from s3 bucket, and kill existing bootnode process
# and launch new bootnode process.

set -euo pipefail
# IFS=$'\n\t'

unset -v progname progdir
progname="${0##*/}"
case "${0}" in
*/*) progdir="${0%/*}";;
*) progdir=".";;
esac

. "${progdir}/util.sh"

ME=$(basename $0)
NOW=$(date +%Y%m%d.%H%M%S)

function usage
{
   cat<<EOF
Usage: $ME [Options] Command
This script is used to launch/terminate bootnode program on bootnode server.

OPTIONS:
   -h             print this help message
   -v             verbose mode
   -G             do the real job (dryrun by default)
   -p port        port number of the bootnode (default: $PORT)
   -b bucket      the bucket name in the s3 (default: $BUCKET)
   -f folder      the folder name in the bucket (default: $FOLDER)
   -S server      the server used to launch bootnode (default: $SERVER)
   -k key         the name of the key (default: $KEY)
   -P profile     the name of the test profile (default: $PROFILE)
   -n bootnode    the name of the bootnode (default: $BN)
   -K p2pkey      the filename of the p2pkey (default: $P2PKEY)
   -L             log P2P connections
   -s session     specify session (default: $SESSION)

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
   FILES=( bootnode )
	FN=go-bootnode-$PORT.sh

   echo "#!/bin/bash" > $FN
   for file in "${FILES[@]}"; do
      echo "curl -O https://$BUCKET.s3.amazonaws.com/$FOLDER/static/$file" >> $FN
   done
   echo "chmod +x bootnode" >> $FN
   echo "./bootnode -version" >> $FN
	chmod +x $FN

   echo ${SSH} ec2-user@${SERVER}
   $DRYRUN ${SSH} ec2-user@${SERVER} "mkdir -p $WORKDIR; pushd $WORKDIR"
   $DRYRUN ${SCP} $FN ec2-user@${SERVER}:$WORKDIR
   [ -e $P2PKEY ] && $DRYRUN ${SCP} $P2PKEY ec2-user@${SERVER}:$WORKDIR/bootnode-$PORT.key
   $DRYRUN ${SSH} ec2-user@${SERVER} "pushd $WORKDIR; ./$FN"
   rm -f $FN
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
   local cmd="pushd $WORKDIR; nohup sudo sh -c 'ulimit -Hn 4096; ulimit -Sn hard; LD_LIBRARY_PATH=. exec ./bootnode -ip $SERVER -port $PORT -key bootnode-$PORT.key ${log_conn_opt}' sh"
   $DRYRUN ${SSH} ec2-user@${SERVER} "$cmd > run-bootnode.log 2>&1 &"
   echo "bootnode node started, sleeping for 5s ..."
   sleep 5
}

function _do_get_multiaddr
{
   local cmd="pushd $WORKDIR >/dev/null; grep -oE '\/ip4\/[0-9.\/tcp\/[0-9]+\/p2p\/[a-zA-Z0-9]{46}' run-bootnode.log"
   MA=$($DRYRUN ${SSH} ec2-user@${SERVER} $cmd)
   echo $MA | tee ${BN}-ma.txt
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
SERVER=
PROFILE=
BN=bootnode
P2PKEY=bootnode.key
SESSION=

unset -v log_conn_opt
log_conn_opt=

while getopts "hvGp:b:f:S:k:P:n:K:Ls:" option; do
   case $option in
      v) VERBOSE=-v ;;
      G) DRYRUN= ;;
      p) PORT=$OPTARG ;;
      b) BUCKET=$OPTARG ;;
      f) FOLDER=$OPTARG ;;
      S) SERVER=$OPTARG ;;
      k) KEY=$OPTARG ;;
      P) PROFILE=$OPTARG ;;
      n) BN=$OPTARG ;;
      K) P2PKEY=$OPTARG ;;
      L) log_conn_opt="-log_conn" ;;
      s) SESSION=$OPTARG ;;
      h|?|*) usage ;;
   esac
done

shift $(($OPTIND-1))

CMD="$@"

if [ "$CMD" = "" ]; then
   CMD=all
fi

KEY=$(find_key_from_ip $SERVER)
KEYDIR=${HSSH_KEY_DIR:-~/.ssh/keys}

SSH="/usr/bin/ssh -o StrictHostKeyChecking=no -o LogLevel=error -i $KEYDIR/$KEY"
SCP="/usr/bin/scp -o StrictHostKeyChecking=no -o LogLevel=error -i $KEYDIR/$KEY"

if [ -n "$SESSION" ]; then
   SUFFIX=$SESSION
else
   SUFFIX=$NOW
fi

WORKDIR=/bootnode/bootnode-$FOLDER-$PROFILE-$SUFFIX

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
