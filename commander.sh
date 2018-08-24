#!/bin/bash
# this script creates the commander instance on AWS
# it uses userdata to init the commander instance to launch the commander
# program automatically after instance booted

set -euo pipefail

ME=$(basename $0)
CONFIG=configs/commander.json
AWS="aws --profile harmony"
JQ="jq -M"

function usage
{
   cat<<EOF
Usage: $ME [Options] Command

This script launch a commander instance and execute commander program upon boot-up.

OPTIONS:
   -h             print this help message
   -n             dry run mode
   -v             verbose mode
   -G             do the real job
   -f config      the configuration file of the commander instance (default: $CONFIG)

Command:
   init           create and init a commander instance (default)
   deinit         terminate the commander instance

Examples:

# create and init a commander instance
 > $ME 

# terminate the commander instance
 > $ME deinit

EOF
   exit 0
}

function _do_init
{
   $DRYRUN $AWS ec2 run-instances --region $REGION --count 1 --instance-type $TYPE --key-name $KEY --security-group-ids $SG --image-id $AMI --user-data $USERDATA --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$TAG}]" --query "Instances[].InstanceId" --output text | tee configs/commander.ip
}

function _do_deinit
{
   instance=$($AWS ec2 describe-instances --region $REGION --no-paginate --filters Name=instance-state-name,Values=running Name=instance-type,Values=$TYPE Name=key-name,Values=$KEY Name=tag:Name,Values=$TAG --query "Reservations[].Instances[].InstanceId" --output text)
   $DRYRUN $AWS ec2 terminate-instances --region $REGION --instance-ids $instance
}

#######################################

DRYRUN=echo

while getopts "hnvGf:" option; do
   case $option in
      n) DRYRUN=echo [DRYRUN] ;;
      v) VERBOSE=-v ;;
      G) DRYRUN= ;;
      f) CONFIG=$OPTARG ;;
      h|?|*) usage ;;
   esac
done

shift $(($OPTIND-1))

CMD="$@"

if [ "$CMD" = "" ]; then
   CMD=init
fi

if [ ! -z $DRYRUN ]; then
   echo '***********************************'
   echo "Please use -G to do the real work"
   echo '***********************************'
fi

#######################################
# find all the configuration data     #
#######################################
REGION=$($JQ .region $CONFIG | tr -d \")
TYPE=$($JQ .type $CONFIG | tr -d \")
AMI=$($JQ .ami $CONFIG | tr -d \")
SG=$($JQ .sg $CONFIG | tr -d \")
KEY=$($JQ .pubkey $CONFIG | tr -d \")
TAG=$($JQ .tag $CONFIG)
USERDATA=$($JQ .userdata $CONFIG | tr -d \")
SUBNET=$($JQ .subnet $CONFIG)

case "$CMD" in
   "init") _do_init ;;
   "deinit") _do_deinit ;;
esac
