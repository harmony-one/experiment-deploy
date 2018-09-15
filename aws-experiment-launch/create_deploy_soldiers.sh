#!/usr/bin/env bash
# this script is used to create/deploy soliders on aws/azure

set -euo pipefail

function usage
{
   ME=$(basename $0)
   cat<<EOF
Usage: $ME [OPTIONS] ACTION

This script is used to create/deploy soliders on cloud providers.
Supported cloud providers: aws,azure

OPTIONS:
   -h             print this help message
   -n             dryrun mode
   -c instances   number of instances in 8 AWS regions (default: $AWS_VM)
   -C instances   number of instances in 3 Azure regions (default: $AZ_VM)
   -s shards      number of shards (default: $SHARD_NUM)
   -t clients     number of clients (default: $CLIENT_NUM)
   -m commander   number of commander (default: $COMMANDER_NUM)
   -p profile     aws profile (default: $PROFILE)
   -i ip_file     file containing ip address of pre-launched VMs
   -l leaders     file containing ip addresses of leader VMs
   -b bucket      specify the bucket containing all test binaries (default: $BUCKET)
   -f folder      specify the folder name in the bucket (default: $FOLDER)
   -r regions     specify the regions for deployment, delimited by , (default: $REGIONS)
   -w instance    the AWS instance type (default: $INSTANCE)
   -u userdata    the userdata file (default: $USERDATA)
   -3             use python3.7 (default: $PYTHON)

ACTION:
   n/a

EXAMPLES:
   $ME -c 100 -C 100 -s 10 -t 1

   $ME -c 100 -s 10 -t 1 -f azure/configs/raw_ip.txt

   $ME -r 1,2,3

EOF
   exit 1
}

function launch_vms
{
   MAX_VM_PER_DEPLOY=800
   if [ $AZ_VM -gt 0 ]; then
   (
      if [ $AZ_VM -gt $MAX_VM_PER_DEPLOY ]; then
         VG_GROUP=$(( $AZ_VM / $MAX_VM_PER_DEPLOY ))
         reminder=$(( $AZ_VM % $MAX_VM_PER_DEPLOY ))
         if [ $reminder -gt 1 ]; then
            VG_GROUP=$(( $VG_GROUP + 1 ))
         fi
      else
         VG_GROUP=1
      fi
      echo "$(date) Creating $VG_GROUP resource groups at 3 Azure regions"
      pushd $ROOTDIR/azure
      ./go-az.sh -g $VG_GROUP init

      echo "$(date) Creating $AZ_VM instances at 3 Azure regions"
      ./go-az.sh -g $VG_GROUP launch $AZ_VM
      popd
   ) &
   fi

   echo "Change userdata file"
   sed "-e s,^BUCKET=.*,BUCKET=${BUCKET}," -e "s,^FOLDER=.*,FOLDER=${FOLDER}/," $USERDATA > $USERDATA.aws

   echo "$(date) Creating $AWS_VM instances at 8 AWS regions"
   $PYTHON ./create_solider_instances.py --profile ${PROFILE}-ec2 --regions $REGIONS --instances $AWS_VMS --instancetype $INSTANCE --userdata $USERDATA.aws --tag $USERID

   echo "Change go-commander.sh"
   sed "-e s,^BUCKET=.*,BUCKET=${BUCKET}," -e "s,^FOLDER=.*,FOLDER=${FOLDER}," $ROOTDIR/aws/go-commander.template > $ROOTDIR/aws/go-commander.sh

   # wait for the background task to finish
   wait
   if [ $AZ_VM -gt 0 ]; then
      cp $ROOTDIR/azure/configs/benchmark.rg.* logs/$TS
   fi

   echo "Sleep for $SLEEP_TIME seconds"
   sleep $SLEEP_TIME
}

function collect_ip
{
   echo "Collecting IP addresses from AWS"
   $PYTHON ./collect_public_ips.py --profile ${PROFILE}-ec2 --instance_output instance_output.txt

   if [ $AZ_VM -gt 0 ]; then
   (
      echo "Collecting IP addresses from Azure"
      pushd $ROOTDIR/azure
      ./go-az.sh listip
      popd
   ) &
   fi

   wait
}

function generate_distribution
{
   if [[ $AZ_VM -gt 0 && -f $ROOTDIR/azure/configs/raw_ip.txt ]]; then
      echo "Merge raw_ip.txt from Azure"
      cat $ROOTDIR/azure/configs/raw_ip.txt | grep -vE '^ node' >> raw_ip.txt
      cp $ROOTDIR/azure/configs/*.ips logs/$TS
   fi
   if [  -f "$IP_FILE" ]; then
      echo "Merge pre-launched IP address"
      cat $IP_FILE >> raw_ip.txt
   fi

   if [ -f "$LEADERS" ]; then
      cat $LEADERS raw_ip.txt > raw_ip.txt.tmp.$USERID
      mv -f raw_ip.txt.tmp.$USERID raw_ip.txt
   fi

   cp raw_ip.txt logs/$TS

   echo "Generate distribution_config"
   $PYTHON ./generate_distribution_config.py --ip_list_file raw_ip.txt --shard_number $SHARD_NUM --client_number $CLIENT_NUM --commander_number $COMMANDER_NUM

   cp distribution_config.txt logs/$TS
   cat>configs/profile.json<<EOT
{
   "bucket": "$BUCKET",
   "folder": "$FOLDER",
   "sessionID": "$TS"
}
EOT
}

function prepare_commander
{
   echo "Run commander prepare"
   $PYTHON ./commander_prepare.py --ts $TS
}

function upload_to_s3
{
   aws --profile ${PROFILE}-s3 s3 cp $ROOTDIR/aws/go-commander.sh s3://${BUCKET}/${FOLDER}/go-commander.sh --acl public-read
   aws --profile ${PROFILE}-s3 s3 cp distribution_config.txt s3://${BUCKET}/${FOLDER}/distribution_config.txt --acl public-read
   aws --profile ${PROFILE}-s3 s3 sync logs s3://harmony-benchmark/logs
}

################### VARIABLES ###################
AWS_VM=2
AZ_VM=0
SHARD_NUM=2
CLIENT_NUM=1
COMMANDER_NUM=1
SLEEP_TIME=60
PROFILE=harmony
IP_FILE=
BUCKET=unique-bucket-bin
USERID=${WHOAMI:-$USER}
FOLDER=$USERID
ROOTDIR=$(dirname $0)/..
TS=$(date +%Y%m%d.%H%M%S)
REGIONS=1,2,3,4,5,6,7,8
INSTANCE=t2.micro
USERDATA=configs/userdata-soldier.sh
PYTHON=python

while getopts "hnc:C:s:t:m:p:f:b:i:r:w:u:3l:" option; do
   case $option in
      n) DRYRUN=--dry-run ;;
      c) AWS_VM=$OPTARG ;;
      C) AZ_VM=$OPTARG ;;
      s) SHARD_NUM=$OPTARG ;;
      t) CLIENT_NUM=$OPTARG ;;
      m) COMMANDER_NUM=$OPTARG ;;
      p) PROFILE=$OPTARG ;;
      i) IP_FILE=$OPTARG ;;
      b) BUCKET=$OPTARG ;;
      f) FOLDER=$OPTARG ;;
      r) REGIONS=$OPTARG ;;
      w) INSTANCE=$OPTARG ;;
      u) USERDATA=$OPTARG ;;
      3) PYTHON=python3.7 ;;
      l) LEADERS=$OPTARG ;;
      h|?|*) usage ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$@

NUM_REGIONS=$(echo $REGIONS | awk -F, ' { print NF-1 } ')
AWS_VMS=$AWS_VM
for i in $(seq 1 $NUM_REGIONS); do
   AWS_VMS+=",$AWS_VM"
done

################### MAIN FUNC ###################
mkdir -p logs/$TS
date
launch_vms
date
collect_ip
date
generate_distribution
date
if [ $COMMANDER_NUM -gt 0 ]; then
   prepare_commander
   date
fi
upload_to_s3
date
