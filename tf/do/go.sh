#!/usr/bin/env bash

SSH='ssh -o StrictHostKeyChecking=no -o LogLevel=error -o ConnectTimeout=5 -o GlobalKnownHostsFile=/dev/null'

function usage
{
   local me=$(basename $0)
   cat<<EOT
Usage: $me blskey_index
This is a wrapper script used to manage/launch the DO nodes using terraform scripts.
PREREQUISITE:
* this script can only be run on devop.hmny.io host.
* make sure you have set DIGITAL_OCEAN_TOKEN environment variable.
OPTIONS:
   -h                               print this help message
COMMANDS:
   new [list of index]              list of blskey index
   rclone [list of ip]              list of IP addresses to run rclone 
   wait [list of ip]                list of IP addresses to wait until rclone finished, check every minute
   uptime [list of ip]              list of IP addresses to update uptime robot, will generate uptimerobot.sh cli
EXAMPLES:
   $me new 308
   $me rclone 1.2.3.4
   $me wait 1.2.3.4 2.2.2.2
   $me uptime 1.2.3.4 2.2.2.2
EOT

   exit 0
}

declare -A gzones
declare -a allzones

function init_check
{
   if [ -z "$DIGITAL_OCEAN_TOKEN" ]; then
      echo Please specify the token variable
      echo export DIGITAL_OCEAN_TOKEN=\"your_digital_ocean_token\"
      exit 1
   fi
}

function get_regions
{
   i=0
   while read -r line; do
      read region up <<< $line
      allregions[$i]=$region
      (( i++ ))
   done < r.list
}

function _do_launch_one
{
   local index=$1

   if [ -z "$index" ]; then
      echo blskey_index is empty, ignoring
      return
   fi

   if [[ $index -le 0 || $index -ge 680 ]]; then
      echo index: $index is out of bound, ignoring
      return
   fi

   region=${allregions[$RANDOM % ${#allregions[@]}]}

   shard=$(( $index % 4 ))

   terraform apply -var "blskey_index=$index" -var "droplet_region=$region" -var "shard=$shard" -var "do_token=$DIGITAL_OCEAN_TOKEN" -auto-approve || return
   sleep 3
   IP=$(terraform output | grep 'public_ip = ' | awk -F= ' { print $2 } ' | tr -d ' ')
   sleep 1
   mv -f terraform.tfstate states/terraform.tfstate.do.$index

   
}

function new_instance
{
   indexes=$@
   rm -f ip.txt
   for i in $indexes; do
      _do_launch_one $i
      echo $IP >> ip.txt
   done
}

# use rclone to sync harmony db
function rclone_sync
{
   ips=$@
   for ip in $ips; do
      $SSH root@$ip 'nohup /root/rclone.sh > rclone.log 2> rclone.err < /dev/null &'
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
         rc=$($SSH root@$ip 'pgrep -n rclone')
         if [ -n "$rc" ]; then
            echo "rclone is running on $ip. pid: $rc."
         else
            echo "rclone is not running on $ip."
         fi
         hmy=$($SSH root@$ip 'pgrep -n harmony')
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
      $SSH root@$ip 'tac latest/zerolog*.log | grep -m 1 BINGO'
   done
   date
}

function update_uptime
{
   ips=$@
   for ip in $ips; do
      idx=$($SSH root@$ip 'cat index.txt')
      shard=$(( $idx % 4 ))
      echo ./uptimerobot.sh -t n1 -i $idx update m5-$idx $ip $shard
      echo ./uptimerobot.sh -t n1 -i $idx -G update m5-$idx $ip $shard
   done
}

while getopts "hv" option; do
   case $option in
      v) VERBOSE=true ;;
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
get_regions

case $CMD in
   new) new_instance $@ ;;
   rclone) rclone_sync $@ ;;
   wait) do_wait $@ ;;
   uptime) update_uptime $@ ;;
   *) usage ;;
esac