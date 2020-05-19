#!/usr/bin/env bash

SSH='ssh -o StrictHostKeyChecking=no -o LogLevel=error -o ConnectTimeout=5 -o GlobalKnownHostsFile=/dev/null'
HARMONYDB=harmony.go
SYNC=true
INSTANCE=n2-standard-2

# assuming 4 shard, calculate the shard number based on index number, mod 4
NUM_SHARDS=4

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

function usage
{
   local me=$(basename $0)
   cat<<EOT
Usage: $me blskey_index
This is a wrapper script used to manage/launch the GCP nodes using terraform scripts.

PREREQUISITE:
* you have to have gcloud cli tools included and project (benchmark-209420) configured.
* this script can only be run on devop.hmny.io host.
* make sure you have the json file for gcp and set GOOGLE_CLOUD_KEYFILE_JSON environment variable.

OPTIONS:
   -h                               print this help message
   -i <instance type>               set the proper instance type (default: $INSTANCE)
   -S                               disable state pruning for the node (default: $SYNC)


COMMANDS:
   new [list of index]              list of blskey index
   rclone [list of ip]              list of IP addresses to run rclone 
   wait [list of ip]                list of IP addresses to wait until rclone finished, check every minute
   uptime [list of ip]              list of IP addresses to update uptime robot, will generate uptimerobot.sh cli
   newmk [list of index]            launch a multi-key node with list of index keys, all indexes have to be in the same shard

EXAMPLES:
   $me new 308
   $me rclone 1.2.3.4

   $me wait 1.2.3.4 2.2.2.2
   $me uptime 1.2.3.4 2.2.2.2

   $me newmk 203 207 211

EOT

   exit 0
}

declare -A gzones
declare -a allzones

function init_check
{
   if [ -z "$GOOGLE_CLOUD_KEYFILE_JSON" ]; then
      echo Please specify the keyfile json variable
      echo export GOOGLE_CLOUD_KEYFILE_JSON=\"path_to_the_key_json_file\"
      exit 1
   fi

   if [ ! -f "$GOOGLE_CLOUD_KEYFILE_JSON" ]; then
      echo Can\'t find $GOOGLE_CLOUD_KEYFILE_JSON 
      exit 1
   fi

   mkdir -p states
}

function get_zones
{
   i=0
   while read -r line; do
      read zone region up <<< $line
      gzones["$zone"]="$region"
      allzones[$i]=$zone
      (( i++ ))
   done < z.list
}

function _do_launch_one
{
   local index=$1
   local tag=$2

   if [ -z "$index" ]; then
      echo blskey_index is empty, ignoring
      return
   fi

   if [[ $index -le 0 || $index -ge 680 ]]; then
      echo index: $index is out of bound, ignoring
      return
   fi

   zone=${allzones[$RANDOM % ${#allzones[@]}]}
   region=${gzones[$zone]}

   shard=$(( $index % ${NUM_SHARDS} ))

   vars=(
      -var "blskey_indexes=$tag"
      -var "region=$region"
      -var "zone=$zone"
      -var "shard=$shard"
      -var "node_instance_type=$INSTANCE"
   )
# enable state pruning
   if $SYNC; then
      vars+=(
         -var "node_volume_size=30"
      )
   fi

   terraform apply "${vars[@]}" -auto-approve || return
   sleep 3
   IP=$(terraform output | grep 'ip = ' | awk -F= ' { print $2 } ' | tr -d ' ')
   NAME=$(terraform output | grep 'name = ' | awk -F= ' { print $2 } ' | tr -d ' ')
   sleep 1
   mv -f terraform.tfstate states/terraform.tfstate.gcp.$index

}

function new_instance
{
   indexes=$@
   rm -f ip.txt
   cp -f files/harmony-1.service files/service/harmony.service
   for i in $indexes; do
      _do_launch_one $i
      echo $IP >> ip.txt
   done
}

# copy one blskey keyfile files/blskeys directory
function _do_copy_blskeys
{
   index=$1
   key=$(grep "Index:...$index " $HARMONYDB | grep -oE 'BlsPublicKey:..[a-z0-9]+' | cut -f2 -d: | tr -d \" | tr -d " ")
   if [ ! -e files/blskeys/${key}.key ]; then
      aws s3 cp s3://harmony-secret-keys/bls/${key}.key files/blskeys/${key}.key
   fi
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
      $SSH gce-user@$ip "nohup /home/gce-user/rclone.sh $folder > rclone.log 2> rclone.err < /dev/null &"
   done
}

# copy bls.pass to .hmy/blskeys
function copy_mk_pass
{
   ips=$@
   for ip in $ips; do
      $SSH gce-user@$ip 'cd .hmy/blskeys; for f in *.key; do p=${f%%.key}; cp /home/gce-user/bls.pass $p.pass; done'
   done
}

# new host with multiple bls keys
function do_new_mk
{
   indexes=( $@ )
   shard=-1
   for idx in ${indexes[@]}; do
      idx_shard=$(( $idx % ${NUM_SHARDS} ))
      if [ $shard == -1 ]; then
         shard=$idx_shard
      else
         if [ $shard != $idx_shard ]; then
            errexit "shard: $shard should be identical. $idx is in shard $idx_shard."
         fi
      fi
   done
   i_name=$(echo $INSTANCE | cut -f1 -d-)
   # clean the existing blskeys
   rm -f files/blskeys/*.key
   rm -f files/multikey.txt

   for idx in ${indexes[@]}; do
      _do_copy_blskeys $idx
      echo $idx >> files/multikey.txt
   done
   tag=$(cat files/multikey.txt | tr "\n" "-" | sed "s/-$//")
   cp -f files/harmony-mk.service files/service/harmony.service
   _do_launch_one ${indexes[0]} $tag
   gcloud compute instances add-labels $NAME --zone $zone --labels="name=s${shard}-${i_name}-${tag},shard=${shard},index=${tag},type=validator"

   copy_mk_pass $IP
   rclone_sync $IP
   do_wait $IP
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
         rc=$($SSH gce-user@$ip 'pgrep -n rclone')
         if [ -n "$rc" ]; then
            echo "rclone is running on $ip. pid: $rc."
         else
            echo "rclone is not running on $ip."
         fi
         hmy=$($SSH gce-user@$ip 'pgrep -n harmony')
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

   for ip in $ips; do
      $SSH gce-user@$ip 'tac latest/zerolog*.log | grep -m 1 BINGO'
   done
   date
}

function update_uptime
{
   ips=$@
   for ip in $ips; do
      idx=$($SSH gce-user@$ip 'cat index.txt')
      shard=$(( $idx % ${NUM_SHARDS} ))
      echo ./uptimerobot.sh -t n1 -i $idx update m5-$idx $ip $shard
      echo ./uptimerobot.sh -t n1 -i $idx -G update m5-$idx $ip $shard
   done
}

while getopts "hvSi:" option; do
   case $option in
      v) VERBOSE=true ;;
      S) SYNC=false ;;
      i) INSTANCE=${OPTARG} ;;
      h|?|*) usage ;;
   esac
done

shift $(($OPTIND-1))

CMD="$1"
shift

if [ -z "$CMD" ]; then
   usage
fi

init_check
get_zones

case $CMD in
   new) new_instance $@ ;;
   rclone) rclone_sync $@ ;;
   wait) do_wait $@ ;;
   uptime) update_uptime $@ ;;
   newmk) do_new_mk $@ ;;
   *) usage ;;
esac
