#!/usr/bin/env bash

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
   -h                            print this help message

COMMANDS:
   new [list of index]           list of blskey index
   rclone [list of ip]           list of IP addresses to run rclone 

EXAMPLES:
   $me new 308
   $me rclone 1.2.3.4

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
   for i in $indexes; do
      _do_launch_one $i
   done
}

# use rclone to sync harmony db
function rclone_sync
{
   ips=$@
   for ip in $ips; do
      ssh gce-user@$ip 'nohup /home/gce-user/rclone.sh > rclone.log 2> rclone.err < /dev/null &'
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
   *) usage ;;
esac
