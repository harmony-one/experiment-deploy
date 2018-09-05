#!/bin/bash
# this script is used to launch/terminate instances in AWS regions

set -euo pipefail

function usage
{
   ME=$(basename $0)
   cat<<EOF
Usage: $ME [Options] ACTION

This script is used to manage instances in AWS regions

OPTIONS:
   -h             print this help message
   -n             dry run mode (default if dryrun)
   -v             verbose mode
   -G             do the real job
   -e filter      extra filters (default: $EXTRA)
   -r region      list of regions to import the key, separated by, ex: pdx, sfo, ... (default: $REGIONS)
   -l lt-*        launch template id
   -c count       launch count number of instances (default: $COUNT)
   -i config      launch configuration json file (default: $CONFIG)

ACTION:
   list           list all the instances
   terminate      terminate all the instances
   launch         launch instances based on launch template
   server         launch one server instance based on launch template

EXAMPLES:

  $ME -e running -r pdx

EOF
   exit 0
}

function get_region_aws_name
{
   local code=$1

   case "$code" in
      "sfo") echo us-west-1 ;;
      "pdx") echo us-west-2 ;;
      "iad") echo us-east-1 ;;
      "cmh") echo us-east-2 ;;
      "fra") echo eu-central-1 ;;
      "dub") echo eu-west-1 ;;
      "syd") echo ap-southeast-2 ;;
      "nrt") echo ap-northeast-1 ;;
      "sin") echo ap-southeast-1 ;;
   esac
}

DRYRUN=echo
AWS='aws --profile harmony'
JQ=$(which jq)
COUNT=1
REGIONS="pdx iad sfo fra dub syd"
EXTRA=running
CONFIG=awsconfig.json
LTID=

while getopts "hnvGe:r:l:c:i:" option; do
   case $option in
      n) DRYRUN=--dry-run ;;
      v) VERBOSE=-v ;;
      G) DRYRUN= ;;
      e) EXTRA=$OPTARG ;;
      r) REGIONS=$OPTARG ;;
      c) COUNT=$OPTARG ;;
      l) LTID=$OPTARG ;;
      i) CONFIG=$OPTARG ;;
      h|?|*) usage ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$@

if [ ! -z $DRYRUN ]; then
   echo '***********************************'
   echo "Please use -G to do the real work"
   echo '***********************************'
fi

function _count_ec2_instance
{
  local filter=$1
  local regions=$2

  for r in $REGIONS; do
     local region=$(get_region_aws_name $r)
      local t=0
      cmd="$AWS --region $region ec2 describe-instances --no-paginate --filters Name=instance-state-name,Values=$filter"
      output=$($cmd)
      count=$(echo $output | $JQ '.Reservations | length')
      for idx in $(seq 0 $count); do
        len=$(echo $output | $JQ ".Reservations[$idx].Instances | length")
        for i in $(seq 0 $len); do
          i_id=$(echo $output | $JQ ".Reservations[$idx].Instances[$i].InstanceId")
          i_type=$(echo $output | $JQ ".Reservations[$idx].Instances[$i].InstanceType")
          i_ip=$(echo $output | $JQ ".Reservations[$idx].Instances[$i].PublicDnsName")
          if [ "$i_id" != "null" ]; then
             echo $i_id : $i_type : $i_ip
             (( t++ ))
          fi
        done
      done
      echo $t $EXTRA instances in $r/$region
      echo "##########"
  done
}

function _terminate_ec2_instance
{
  local filter=running
  local regions=$1

  for r in $REGIONS; do
     local region=$(get_region_aws_name $r)
     local t=0
     cmd="$AWS --region $region ec2 describe-instances --no-paginate --filters Name=instance-state-name,Values=$filter"
     output=$($cmd)
     count=$(echo $output | $JQ '.Reservations | length')
     instance_ids=()
     for idx in $(seq 0 $count); do
        len=$(echo $output | $JQ ".Reservations[$idx].Instances | length")
        for i in $(seq 0 $len); do
          i_id=$(echo $output | $JQ .Reservations[$idx].Instances[$i].InstanceId | tr -d \")
          i_type=$(echo $output | $JQ .Reservations[$idx].Instances[$i].InstanceType | tr -d \")
          if [[ "$i_id" != "null" ]]; then
             instance_ids[$t]=$i_id
             (( t++ ))
          fi
        done
     done
     if [ ${#instance_ids[@]} -gt 0 ]; then
        cmd="$AWS --region $region ec2 terminate-instances --instance-ids ${instance_ids[@]}"
        if [ -n "$DRYRUN" ]; then
           echo $cmd
        else
           output=$($cmd)
           count=$(echo $output | $JQ '.TerminatingInstances | length')
           local t=0
           for idx in $(seq 0 $count); do
              i_id=$(echo $output | $JQ .TerminatingInstances[$idx].InstanceId | tr -d \")
              i_state=$(echo $output | $JQ .TerminatingInstances[$idx].CurrentState.Name | tr -d \")
              if [[ "$i_id" != "null" ]]; then
                 echo $i_id : $i_state
                 (( t++ ))
              fi
           done
           echo terminatd $t instances in $r/$region
        fi
     else
        echo NO running instances in $r/$region
     fi
     echo "##########"
  done
}

function _launch_ec2_instance
{
   local count=$1
   local ltid=$2
   local regions=$3

   for r in $REGIONS; do
      local region=$(get_region_aws_name $r)
      local t=0
      cmd="$AWS --region $region ec2 run-instances --launch-template LaunchTemplateId=$ltid --count=$count"
      if [ -n "$DRYRUN" ]; then
         echo $cmd
      else
         output=$($cmd)
         echo $output
      fi
   done
}

function _launch_ec2_server_instance
{
   local config=$1
   local r=$2

   local region=$(get_region_aws_name $r)
   # launch one server instance on pdx
   local serverlt=$($JQ .$r.serverlt $config | tr -d \")
   cmd="$AWS --region $region ec2 run-instances --launch-template LaunchTemplateId=$serverlt --count=1"
   if [ -n "$DRYRUN" ]; then
      echo $cmd
      return
   fi
   output=$($cmd)
   i_id=$(echo $output | $JQ .Instances[0].InstanceId | tr -d \")
   i_type=$(echo $output | $JQ .Instances[0].InstanceType)
   i_state=$(echo $output | $JQ .Instances[0].State)

   for t in $(seq 0 50) ; do
      # The first running instance should be the server instance
      cmd="$AWS --region $region ec2 describe-instances --instance-ids $i_id"
      output=$($cmd)
      i_state=$(echo $output | $JQ .Reservations[0].Instances[0].State.Name | tr -d \")
      i_ip=$(echo $output | $JQ .Reservations[0].Instances[0].PublicIpAddress | tr -d \")
      if [ "$i_state" != "running" ]; then
         echo waiting for $i_id running ... $t
         sleep 3
      else
         echo launched server instance $i_id/$i_type/$i_ip
         echo $i_ip > server.ip
         return
      fi
   done
}

function _launch_ec2_instance_by_config
{
   local config=$1
   local regions=$2

   for r in $REGIONS; do
      local region=$(get_region_aws_name $r)
      local t=0
      local ltid=$($JQ .$r.ltid $config | tr -d \")
      local count=$($JQ .$r.count $config)
      cmd="$AWS --region $region ec2 run-instances --launch-template LaunchTemplateId=$ltid --count=$count"
      if [ -n "$DRYRUN" ]; then
         echo $cmd
      else
         output=$($cmd)
         count=$(echo $output | $JQ ".Instances | length")
         for i in $(seq 0 $count); do
            i_id=$(echo $output | $JQ .Instances[$i].InstanceId)
            i_type=$(echo $output | $JQ .Instances[$i].InstanceType)
            i_state=$(echo $output | $JQ .Instances[$i].State.Name)
            if [ "$i_id" != "null" ]; then
               echo $i_id : $i_type : $i_state
               (( t++ ))
            fi
         done
         echo launched $t instances in $r/$region
      fi
   done
}

case "$ACTION" in
   "list")
      _count_ec2_instance $EXTRA "$REGIONS" ;;
   "terminate")
      _terminate_ec2_instance "$REGIONS" ;;
   "launch")
      if [ -n "$LTID" ]; then
         _launch_ec2_instance $COUNT $LTID "$REGIONS"
      elif [ -e "$CONFIG" ]; then
         _launch_ec2_instance_by_config $CONFIG "$REGIONS"
      else
         echo Please specify either launch id or launch config file.
      fi
      ;;
   "server")
      _launch_ec2_server_instance $CONFIG pdx ;;
   *)
      usage
esac
