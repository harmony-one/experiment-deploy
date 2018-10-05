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

ACTION:
   list        list all running instances (id,type,name) - default
   delete      delete all running instances


EXAMPLES:

   $ME -g leo -G
EOT

   exit 1
}

function terminate_ids
{
   for r in ${REGIONS[@]}; do
      NUM=$(wc -l $r.ids | cut -f 1 -d ' ')
      echo terminating instances in $r: $NUM instances
      if [ $NUM -gt 500 ]; then
         split -l 300 --additional-suffix=.ids $r.ids $r-split-
         for f in $r-split-*.ids; do
            id=$(cat $f | cut -f 1 | tr '\n' ' ')
            if [ "$id" != "" ]; then
               $DRYRUN $AWS --region $r ec2 terminate-instances --instance-ids $id --query 'TerminatingInstances[*].InstanceId'
            else
               echo no $r.ids file
            fi
         done
         rm -f $r-split-*.ids
      else
         id=$(cat $r.ids | cut -f 1 | tr '\n' ' ')
         if [ "$id" != "" ]; then
            $DRYRUN $AWS --region $r ec2 terminate-instances --instance-ids $id --query 'TerminatingInstances[*].InstanceId'
         else
            echo no $r.ids file
         fi
      fi
   done
}

function list_ids
{
   echo Listing running instance with name filter \"$FILTER\" ..

   for r in ${REGIONS[@]}; do
      $AWS --region $r ec2 describe-instances --no-paginate --filters Name=instance-state-name,Values=running | jq -r '.Reservations[].Instances[] | {id:.InstanceId, type:.InstanceType, tag:.Tags[]?} | [.id, .type, .tag.Value ] | @tsv ' | grep -E $FILTER > $r.ids
      echo $(wc -l $r.ids | cut -f1 -d' ') running instances found in $r
   done
}

############################### GLOBAL VARIABLES ###############################
DRYRUN=echo
AWS=aws
FILTER=${WHOAMI:-USER}

############################### MAIN FUNCTION    ###############################
while getopts "hGg:" option; do
   case $option in
      h) usage ;;
      G) DRYRUN= ;;
      g) FILTER=$OPTARG ;;
   esac
done

shift $(($OPTIND-1))

ACTION=${1:-list}

case "$ACTION" in
   "list") list_ids ;;
   "delete")
      terminate_ids
      if [ -n "$DRYRUN" ]; then
         echo
         echo "******************************"
         echo Use -G to execute the command!
         echo "******************************"
      fi
      ;;
esac


