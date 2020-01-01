#!/usr/bin/env bash

SSH='ssh -o StrictHostKeyChecking=no -o LogLevel=error -o ConnectTimeout=5 -o GlobalKnownHostsFile=/dev/null'

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

COMMANDS:
   new [list of index]              list of blskey index
   rclone [list of ip]              list of IP addresses to run rclone 
   wait [list of ip]                list of IP addresses to wait until rclone finished, check every minute
   uptime [list of index:ip pair]   list of index:IP pair to update uptime robot

EXAMPLES:
   $me new 308
   $me rclone 1.2.3.4

   $me wait 1.2.3.4 2.2.2.2
   $me uptime 308:1.2.3.4 404:2.2.2.2

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

   terraform apply -var "blskey_index=$index" -var "region=$region" -var "zone=$zone" -auto-approve || return
   sleep 3
   IP=$(terraform output | grep 'ip = ' | awk -F= ' { print $2 } ' | tr -d ' ')
   sleep 1
   mv -f terraform.tfstate states/terraform.tfstate.gcp.$index
}

function new_instance
{
   indexes=$@
   rm -f ip.txt
   for i in "$indexes"; do
      _do_launch_one $i
      echo $IP >> ip.txt
   done
}

# use rclone to sync harmony db
function rclone_sync
{
   ips=$@
   for ip in "$ips"; do
      $SSH gce-user@$ip 'nohup /home/gce-user/rclone.sh > rclone.log 2> rclone.err < /dev/null &'
   done
}

function do_wait
{
   ips=$@
   declare -A DONE
   for ip in "$ips"; do
      DONE[$ip]=false
   done

   min=0
   while true; do
      for ip in "$ips"; do
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
      for ip in "$ips"; do
         if ! ${DONE[$ip]}; then
            alldone=false
            break
         fi
      done

      if $alldone; then
         echo All Done!
         return
      fi
      echo "sleeping 60s, $min minutes passed"
      sleep 60
      (( min++ ))
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
get_zones

case $CMD in
   new) new_instance $@ ;;
   rclone) rclone_sync $@ ;;
   wait) do_wait $@ ;;
   uptime) update_uptime $@ ;;
   *) usage ;;
esac
