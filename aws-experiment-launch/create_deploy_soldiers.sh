#!/bin/bash
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
   -p profile     aws profile (default: $PROFILE)

ACTION:
   n/a

EOF
   exit 1
}

AWS_VM=10
AZ_VM=10
SHARD_NUM=5
CLIENT_NUM=1
SLEEP_TIME=10
PROFILE=default
ROOTDIR=$(dirname $0)/..

while getopts "hnc:C:s:t:p:" option; do
   case $option in
      n) DRYRUN=--dry-run ;;
      c) AWS_VM=$OPTARG ;;
      C) AZ_VM=$OPTARG ;;
      s) SHARD_NUM=$OPTARG ;;
      t) CLIENT_NUM=$OPTARG ;;
      p) PROFILE=$OPTARG ;;
      h|?|*) usage ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$@

function launch_vms
{
   (
      echo "Creating $AZ_VM instances at 3 Azure regions"
      date
      pushd $ROOTDIR/azure
      echo "Please init Azure regions before running this script"
      ./go-az.sh launch $AZ_VM
      popd
      date
   ) &

   echo "Creating $AWS_VM instances at 8 AWS regions"
   python create_solider_instances.py --regions 1,2,3,4,5,6,7,8 --instances $AWS_VM,$AWS_VM,$AWS_VM,$AWS_VM,$AWS_VM,$AWS_VM,$AWS_VM,$AWS_VM

   # wait for the background task to finish
   wait

   echo "Sleep for $SLEEP_TIME seconds"
   sleep $SLEEP_TIME
}

function collect_ip
{
   (
      echo "Collecting IP addresses from Azure"
      pushd $ROOTDIR/azure
      ./go-az.sh listip
      popd
   ) &

   echo "Collecting IP addresses from AWS"
   python collect_public_ips.py --instance_output instance_output.txt

   wait
}

function generate_distribution
{
   echo "Generate distribution_config"
   python generate_distribution_config.py --ip_list_file raw_ip.txt --shard_number $SHARD_NUM --client_number $CLIENT_NUM
}

function prepare_commander
{
   echo "Run commander prepare"
   python commander_prepare.py
}

function upload_to_s3
{
   aws --profile $PROFILE s3 cp distribution_config.txt s3://unique-bucket-bin/distribution_config.txt --acl public-read-write
}

####### main #########
date
launch_vms
date
collect_ip
date
generate_distribution
date
prepare_commander
date
upload_to_s3
date
