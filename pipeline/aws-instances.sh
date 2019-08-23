#!/bin/bash

REGIONS=( us-west-1 us-west-2 us-east-1 us-east-2 eu-central-1 eu-west-1 ap-northeast-1 ap-southeast-1 )

function usage
{
   ME=$(basename $0)
   cat<<EOT

Usage: $ME [OPTIONS] ACTION

OPTIONS:
   -h          print this help message
   -G          do the real work, not dryrun
   -g filter   grep filter to filter out the instances (default: $FILTER)
   -p profile  find all running instance with specified Profile tag

ACTION:
   list        list all running instances (id,type,name) - default
   delete      delete all running instances
   unprotect   disable termination protection
   unmonitor   disable detailed cloud watch monitor


EXAMPLES:

   $ME -g leo -G
EOT

   exit 1
}

function disable_protection
{
   for r in ${REGIONS[@]}; do
      [ ! -e $r.ids ] && continue
      NUM=$(wc -l $r.ids | cut -f 1 -d ' ')
      cat $r.ids
      read -p "Please CONFIRM to DISABLE the protection of those instances (y/N)?" yesno
      echo
      if [[ "$yesno" == "y" || "$yesno" == "Y" ]]; then
         while read line; do
            echo "disabling termination protection of $line ..."
            id=$(echo "$line" | cut -f 1)
            $DRYRUN $AWS --region $r ec2 modify-instance-attribute --no-disable-api-termination --instance-id $id
         done<$r.ids
      fi
   done
}

function disable_monitor
{
   for r in ${REGIONS[@]}; do
      [ ! -e $r.ids ] && continue
      while read line; do
         echo "disabling detailed monitoring $line ..."
         id=$(echo "$line" | cut -f 1)
         $DRYRUN $AWS --region $r ec2 unmonitor-instances --instance-id $id
      done<$r.ids
   done
}

function terminate_ids
{
   for r in ${REGIONS[@]}; do {
      [ ! -e $r.ids ] && continue
      NUM=$(cat $r.ids | cut -f 1 | sort -u | wc -l)
      echo terminating instances in $r: $NUM instances
      if [ $NUM -gt 500 ]; then
         split -l 300 --additional-suffix=.ids $r.ids $r-split-
         for f in $r-split-*.ids; do
            id=$(cat $f | cut -f 1 | sort -u | tr '\n' ' ')
            if [ "$id" != "" ]; then
               $DRYRUN $AWS --region $r ec2 terminate-instances --instance-ids $id --query 'TerminatingInstances[*].InstanceId'
            else
               echo no $r.ids file
            fi
         done
         rm -f $r-split-*.ids
      else
         id=$(cat $r.ids | cut -f 1 | sort -u | tr '\n' ' ')
         if [ "$id" != "" ]; then
            $DRYRUN $AWS --region $r ec2 terminate-instances --instance-ids $id --query 'TerminatingInstances[*].InstanceId'
         else
            echo no $r.ids file
         fi
      fi
   } & done
   wait
}

function list_ids
{

   for r in ${REGIONS[@]}; do {
      if [ -n "$PROFILE" ]; then
         echo Listing running instance with tag: Profile =\> \"$PROFILE\" at $r ...
         query=".Reservations[].Instances[] | {id:.InstanceId, type:.InstanceType, tag:.Tags[]?} | select (.tag.Value | contains (\"-$PROFILE-\")) | [.id, .type, .tag.Value ] | @tsv "
         $AWS --region $r ec2 describe-instances --no-paginate --filters "Name=instance-state-name,Values=running" "Name=tag:Profile,Values=${PROFILE}" | jq -r "$query" | sort > $r.ids
      else
         echo Listing running instance with name filter \"$FILTER\" at $r ...
         $AWS --region $r ec2 describe-instances --no-paginate --filters "Name=instance-state-name,Values=running" | jq -r '.Reservations[].Instances[] | {id:.InstanceId, type:.InstanceType, tag:.Tags[]?} | [.id, .type, .tag.Value ] | @tsv ' | grep -E $FILTER | sort > $r.ids
      fi
      NUM_INST=$(cat $r.ids | cut -f 1 | sort -u | wc -l)
      echo ${NUM_INST} running instances found in $r
      if [ ${NUM_INST} == 0 ]; then
         rm -f $r.ids
      fi
   } & done
   wait
   num=$(cat *.ids | cut -f 1 | sort -u |wc -l)
   echo $num running instances found with name filter: \"$FILTER\"
}

############################### GLOBAL VARIABLES ###############################
DRYRUN=echo
AWS=aws
FILTER=${WHOAMI:-USER}
PROFILE=

############################### MAIN FUNCTION    ###############################
while getopts "hGg:p:" option; do
   case $option in
      h) usage ;;
      G) DRYRUN= ;;
      g) FILTER=$OPTARG ;;
      p) PROFILE=$OPTARG ;;
   esac
done

shift $(($OPTIND-1))

ACTION=${1:-list}

case "$ACTION" in
   "list")
      list_ids
      exit 0 ;;
   "unprotect")
      disable_protection ;;
   "delete")
      terminate_ids ;;
   "unmonitor")
      disable_monitor ;;
esac

if [ -n "$DRYRUN" ]; then
   echo
   echo "******************************"
   echo Use -G to execute the command!
   echo "******************************"
fi
