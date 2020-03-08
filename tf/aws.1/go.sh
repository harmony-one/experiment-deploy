#!/usr/bin/env bash
# this script is used to launch Harmony validatro nodes using terraform recipe

source ./regions.sh
ME=`basename $0`
SSH='ssh -o StrictHostKeyChecking=no -o LogLevel=error -o ConnectTimeout=5 -o GlobalKnownHostsFile=/dev/null'
HARMONYDB=harmony.go

set -o pipefail
# set -x

if [ "$(uname -s)" == "Darwin" ]; then
   TIMEOUT=gtimeout
else
   TIMEOUT=timeout
fi

if [[ -z "$WHOAMI" || "$WHOAMI" == "ec2-user" ]]; then
   echo WHOAMI is not set or set to ec2-user
   exit 0
fi

if [ -z "$HMY_PROFILE" ]; then
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
NODEDB=$(realpath ../../../nodedb)

function usage
{
   cat<<EOF
Usage: $ME [Options] Command
This script will be used to manage AWS terraform nodes: launch new one, run rclone, wait for rclone finish

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
   -S                         enabled state pruning for the node (default: $SYNC)
   -N nodedb-directory        specify the directory of the nodedb (default: $NODEDB)

   -i <instance type>         specify instance type (default: $INSTANCE)
                              supported type: $(echo ${!SPOT[@]} | tr " " ,)

   -r <region>                specify the region (default: $REG)
                              supported region: $(echo ${REGIONS[@]} | tr " " ,)
   -M multi-key-node-index    use this node to host multi-key
   -K blskey-directory        specify the directory of all blskeys (default: $KEYDIR)


COMMANDS:
   new [list of index]        list of index of the harmony node in internal/genesis/harmony.go, delimited by space
   rclone [list of ip]        list of IP addresses to do rlcone, delimited by space
   wait [list of ip]          list of IP addresses to wait until rclone finished, check every minute
   uptime [list of ip]        list of IP addresses to update uptime robot, will generate uptimerobot.sh cli
   status [list of ip]        list of IP addresses to check latest block height
   replace [list of index]    terminate old instances replaced by the new one, find the IP of old instance using the index from nodedb
   multikey [list of index]   copy all the keys specified by index to the multikey host (must use -M)
   mkuptime [list of index]   list of index to be updated in uptimerobot (must use -M)
   newmk [list of index]      launch a multi-key node with list of index keys, all indexes have to be in the same shard

EXAMPLES:

   $ME -v

   $ME new 20 30 5

   $ME -S -i c5.large new 20 30 5

   $ME -S rclone 12.34.56.78 123.234.123.234

   $ME wait 12.34.56.78 123.234.123.234

   $ME uptime 12.34.56.78 123.234.123.234 > upt.sh

   $ME replace 200 20 10 > repl.sh

   $ME -M 100 multikey 100 200 300

   $ME -M 10 mkuptime 10 22 42 > upmk.sh

   $ME newmk 20 40 80

EOF
   exit 0
}

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
   shard=$(( $index % 4 ))

   vars=(
      -var "blskey_index=$index" 
      -var "default_shard=$shard"
      -var "node_instance_type=$INSTANCE" 
      -var "spot_instance_price=${SPOT[$INSTANCE]}"
   )
# enable state pruning
   if $SYNC; then
      vars+=(
         -var "node_volume_size=30"
      )
   fi

   if [ "$REG" == "random" ]; then
      REG=${REGIONS[$RANDOM % ${#REGIONS[@]}]}
   fi

   vars+=(
      -var "aws_region=$REG"
   )
   terraform apply "${vars[@]}" -auto-approve || return
   sleep 3
   IP=$(terraform output -json | jq -rc '.public_ip.value  | @tsv')
   ID=$(terraform output -json | jq -rc '.instance_id.value  | @tsv')
   echo "$IP:$ID" >> $OUTPUT
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
   rm -f ip.txt
   i_name=$(echo $INSTANCE | cut -f1 -d.)
   cp -f files/harmony-1.service files/service/harmony.service
   for i in $indexes; do
      _do_launch_one $i
      echo $IP >> ip.txt
      shard=$(( $i % 4 ))
      aws --profile mainnet --region $REG ec2 create-tags --resources $ID --tags "Key=Name,Value=s${shard}-${i_name}-$i" "Key=Shard,Value=${shard}" "Key=Index,Value=$i" "Key=Type,Value=node"
   done

   do_state_sync
}

# copy one blskey keyfile files/blskeys directory
function _do_copy_blskeys
{
   index=$1
   key=$(grep "Index:...$index " $HARMONYDB | grep -oE 'BlsPublicKey:..[a-z0-9]+' | cut -f2 -d: | tr -d \" | tr -d " ")
   aws s3 cp s3://harmony-secret-keys/bls/${key}.key files/blskeys/${key}.key
}

# new host with multiple bls keys
function do_new_mk
{
   indexes=( $@ )
   shard=-1
   for idx in ${indexes[@]}; do
      idx_shard=$(( $idx % 4 ))
      if [ $shard == -1 ]; then
         shard=$idx_shard
      else
         if [ $shard != $idx_shard ]; then
            errexit "shard: $shard should be identical. $idx is in shard $idx_shard."
         fi
      fi
   done
   i_name=$(echo $INSTANCE | cut -f1 -d.)
   # clean the existing blskeys
   rm -f files/blskeys/*.key
   rm -f files/multikey.txt

   for idx in ${indexes[@]}; do
      _do_copy_blskeys $idx
      echo $idx >> files/multikey.txt
   done
   tag=$(cat files/multikey.txt | tr "\n" "-" | sed "s/-$//")
   cp -f files/harmony-mk.service files/service/harmony.service
   _do_launch_one ${indexes[0]}
   aws --profile mainnet --region $REG ec2 create-tags --resources $ID --tags "Key=Name,Value=s${shard}-${i_name}-${tag}" "Key=Shard,Value=${shard}" "Key=Index,Value=${tag}" "Key=Type,Value=node"
}

# use rclone to sync harmony db
function rclone_sync
{
   ips=$@
   if $SYNC; then
      folder=mainnet.min
   else
      folder=mainnet
   fi

   for ip in $ips; do
      $SSH ec2-user@$ip "nohup /home/ec2-user/rclone.sh $folder > rclone.log 2> rclone.err < /dev/null &"
   done
}

function do_wait
{
   ips=$@
   declare -A DONE
   for ip in $ips; do
      DONE[$ip]=false
   done

   min=0
   while true; do
      for ip in $ips; do
         rc=$($SSH ec2-user@$ip 'pgrep -n rclone')
         if [ -n "$rc" ]; then
            echo "rclone is running on $ip. pid: $rc."
         else
            echo "rclone is not running on $ip."
         fi
         hmy=$($SSH ec2-user@$ip 'pgrep -n harmony')
         if [ -n "$hmy" ]; then
            echo "harmony is running on $ip. pid: $hmy"
            DONE[$ip]=true
         else
            echo "harmony is not running on $ip."
         fi
      done

      alldone=true
      for ip in $ips; do
         if ! ${DONE[$ip]}; then
            alldone=false
            break
         fi
      done

      if $alldone; then
         echo All Done!
         break
      fi
      echo "sleeping 60s, $min minutes passed"
      sleep 60
      (( min++ ))
   done

   do_status

   date
}

function update_uptime
{
   ips=$@
   i_name=$(echo $INSTANCE | cut -f1 -d.)
   for ip in $ips; do
      idx=$(node_ssh.sh $ip 'cat index.txt')
      shard=$(( $idx % 4 ))
      echo ./uptimerobot.sh -t $i_name -i $idx update "s${shard}-.*-$idx" $ip $shard
      echo ./uptimerobot.sh -t $i_name -i $idx -G update "s${shard}-.*-$idx" $ip $shard
   done
}

function mk_update_uptime
{
   indexes=$@
   if [ -z "$MKHOST" ]; then
      errexit "Please specify multikey host index using -M option"
   fi
   if [ $(echo "$indexes" | wc -w) -lt 2 ]; then
      errexit "Please specify at least 2 idx for multi-key uptime update"
   fi
   mk_ip=$(grep -E :$MKHOST: $NODEDB/mainnet/ip.idx.map | tail -n 1 | cut -f1 -d:)
   mk_name=$(echo "$indexes" | tr " " "-")
   for idx in $indexes; do
      if [ "$idx" == "$MKHOST" ]; then
         i_name=$(echo $INSTANCE | cut -f1 -d.)
         shard=$(( $idx % 4 ))
         # update uptimerobot of multikey host
         echo ./uptimerobot.sh -t $i_name -i $mk_name update "s${shard}-.*-$idx" $mk_ip $shard
         echo ./uptimerobot.sh -t $i_name -i $mk_name -G update "s${shard}-.*-$idx" $mk_ip $shard

      else
         # pause uptimerobot of other hosts
         echo ./uptimerobot.sh pause "s${shard}-.*-$idx"
         echo ./uptimerobot.sh -G pause "s${shard}-.*-$idx"
      fi
   done

}

function do_status
{
   ips=$@
   for ip in $ips; do
      $SSH ec2-user@$ip 'tac latest/zerolog*.log | grep -m 1 BINGO'
   done
}

function do_replace
{
   indexes=$@
   for index in $indexes; do
      ip=$(grep -E :$index: $NODEDB/mainnet/ip.idx.map | tail -n 1 | cut -f1 -d:)
      echo $ip
      id=$($SSH ec2-user@$ip 'curl http://169.254.169.254/latest/meta-data/instance-id')
      region=$($SSH ec2-user@$ip 'curl http://169.254.169.254/latest/meta-data/placement/availability-zone | sed "s/[a-z]$//"')
      echo aws --profile mainnet --region $region ec2 terminate-instances --instance-ids $id --query 'TerminatingInstances[*].InstanceId'
   done
}

function do_copy_multikey
{
   indexes=$@
   if [ -z "$MKHOST" ]; then
      errexit "Please specify multikey host index using -M option"
   fi
   shard=$(( $MKHOST % 4 ))
   mkhost_ip=$(grep -E :$MKHOST: $NODEDB/mainnet/ip.idx.map | tail -n 1 | cut -f1 -d:)
   echo multikey host shard =\> $shard IP =\> $mkhost_ip
   $SSH ec2-user@$mkhost_ip "mkdir -p .hmy/blskeys/"

   for index in $indexes; do
      s=$(( $index % 4 ))
      if [ $s -ne $shard ]; then
         errexit "index:$index doesn't belong to shard $shard. All indexes have to be in the same shard."
      fi
   done
   for index in $indexes; do
      key=$(grep -E "\"$index\"\s+=" variables.tf | cut -f2 -d= | tr -d \" | tr -d " ")
      if [ -e "$KEYDIR/${key}.key" ]; then
         ip=$(grep -E :$index: $NODEDB/mainnet/ip.idx.map | tail -n 1 | cut -f1 -d:)
         echo $index:$ip:${key}.key
         cat "$KEYDIR/${key}.key" | $SSH ec2-user@$mkhost_ip "cat > .hmy/blskeys/${key}.key"
         echo $index |  $SSH ec2-user@$mkhost_ip "cat >> ~/multikey.txt"
      else
         echo found NO $index =\> ${key}.key file, skipping ..
      fi
   done
}

###############################################################################
LOGDIR=../../pipeline/logs/$HMY_PROFILE
DRYRUN=echo
OUTPUT=$LOGDIR/$(date +%F.%H:%M:%S).log
SYNC=false
INSTANCE=c5.large
REG=random
MKHOST=
KEYDIR=$HOME/tmp/blskey

while getopts "hnvGss:d:Si:r:M:K:" option; do
   case $option in
      n) DRYRUN=echo [DRYRUN] ;;
      v) VERBOSE=-v ;;
      G) DRYRUN= ;;
      s) STATEDIR="${OPTARG}" ;;
      d) LOGDIR="${OPTARG}" ;;
      S) SYNC=true ;;
      i) INSTANCE="${OPTARG}" ;;
      r) REG="${OPTARG}" ;;
      M) MKHOST="${OPTARG}" ;;
      K) KEYDIR="${OPTARG}" ;;
      h|?|*) usage ;;
   esac
done

# TODO: verify/validate the command line variables

shift $(($OPTIND-1))

CMD="$1"
shift

if [ -z "$CMD" ]; then
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

case $CMD in
   new) new_instance $@ ;;
   rclone) rclone_sync $@ ;;
   wait) do_wait $@ ;;
   uptime) update_uptime $@ ;;
   status) do_status $@ ;;
   replace) do_replace $@ ;;
   multikey) do_copy_multikey $@ ;;
   mkuptime) mk_update_uptime $@ ;;
   newmk) do_new_mk $@ ;;
   *) usage ;;
esac

# vim:ts=3:sw=3
