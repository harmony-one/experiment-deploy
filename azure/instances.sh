#!/bin/bash

set -euo pipefail

source ./common.sh

function usage
{
   ME=$(basename $0)
   MSG=${1:-''}

   cat<<EOF

Usage: $ME [Options] ACTION

This script is used to manage instances in Azure

Options:
   -h             print this help message
   -n             dryrun mode (default)
   -G             do the real work
   -r region      run in region (supported regions: ${REGIONS[@]})
   -p profile     use profile config file (default: $PROFILE)
   -t template    the resource template file
   -v parameter   the parameter file 
   -c count       count per deployment (max: 200, default: $COUNT)
   -g group       number of deployment (default: $GROUP)
   -s start       starting point of the group number (default: $START)
   -a tag         tag of the resource group (default: $TAG)
   -x prefix      prefix of the subnet (default: $PREFIX)


Action:
   list           list the vm launched
   launch         do deployment to launch instances
   terminate      terminate instances

Examples:
   $ME -r eastus list
   $ME -r eastus -t configs/vm-template-1.json launch
   $ME -r eastus -s 10 -c 100 -g 1 launch
   $ME -r eastus -a 201808-01 -G initregion

----------------------------------
NOTE: $MSG
EOF

   exit 0
}

function do_launch_instance
{
   for region in "${REGIONS[@]}"; do
      if [ -n "$REGION" ]; then
         # run on specificed region
         if [ "$region" != "$REGION" ]; then
            continue
         fi
      fi

      LOG=logs/$region.launch.$TS.log
      ERRLOG=logs/$region.launch.error.$TS.log
      echo $(date) > $LOG
      echo $(date) > $ERRLOG

      if [ "$PARAMETER" == "" ]; then
         parameters=configs/vm-parameters-$region.json
      else
         parameters=$PARAMETER-$region.json
      fi

      NUM=$($JQ ' .parameters.count.value ' $parameters)
      NSG=$($JQ ' .parameters.harmony_benchmark_nsg.value ' $parameters)
      VNET=$($JQ ' .parameters.harmony_benchmark_vnet.value ' $parameters)
      RG=$($JQ " .$region | .rg " $CONFIG)
      echo launching vms in $region/$NUM/$NSG/$VNET
      echo

      END=$(( $START + $GROUP ))
      for s in $(seq $START $END); do
         echo az group deployment create --name "$region.deploy.$TS" --resource-group $RG --template-file "$TEMPLATE" --parameters @${parameters} count=$COUNT start=$s
         date
         $DRYRUN az group deployment create --name "$region.deploy.$TS" --resource-group $RG --template-file "$TEMPLATE" --parameters @${parameters} count=$COUNT start=$s 2>>$ERRLOG >> $LOG
      done

      echo $(date) >> $LOG
      echo $(date) >> $ERRLOG
      echo
   done
}

function do_list_instance
{
   for region in "${REGIONS[@]}"; do
      if [ -n "$REGION" ]; then
         # run on specificed region
         if [ "$region" != "$REGION" ]; then
            continue
         fi
      fi

      local parameters=configs/vm-parameters-$region.json
      RG=$($JQ " .$region | .rg " $CONFIG)

      if [ -n "$DRYRUN" ]; then
         echo az vm list --resource-group $RG --show-details --query '[].{name:name, ip:publicIps, size:hardwareProfile.vmSize}' -o tsv
      else
         LOG=logs/$region.list.$TS.log
         echo $(date) > $LOG
         az vm list --resource-group $RG --show-details --query  '[].{name:name, ip:publicIps, size:hardwareProfile.vmSize}' -o tsv | tee -a $LOG
         echo $(date) >> $LOG
      fi

   done
}

function do_terminate_instance
{
# TODO: confirm before terminate
   for region in "${REGIONS[@]}"; do
      if [ -n "$REGION" ]; then
         # run on specificed region
         if [ "$region" != "$REGION" ]; then
            continue
         fi
      fi

      local parameters=configs/vm-parameters-$region.json
      RG=$($JQ " .$region | .rg " $CONFIG)

      ID=( $(az vm list --resource-group $RG --query '[].id' -o tsv) )
      if [ -n "$DRYRUN" ]; then
         echo az vm delete --yes --no-wait --resource-group $RG --ids "${ID[@]}"
      else
         LOG=logs/$region.delete.$TS.log
         echo $(date) > $LOG
         az vm delete --yes --no-wait --resource-group $RG --ids "${ID[@]}" | tee -a $LOG
         echo $(date) >> $LOG
      fi


   done
}

######################################################

DRYRUN=echo
TS=$(date +%Y%m%d.%H%M%S)
TAG=$(date +%m%d)
REGION=
PROFILE=small
TEMPLATE=configs/vm-template.json
PARAMETER=
COUNT=1
GROUP=1
START=1
PREFIX=10.10.0.0/20

while getopts "hnGr:p:t:v:c:g:s:a:x:" option; do
   case $option in
      r) REGION=$OPTARG ;;
      G) DRYRUN= ;;
      p) PROFILE=$OPTARG ;;
      t) TEMPLATE=$OPTARG ;;
      v) PARAMETER=$OPTARG ;;
      c) COUNT=$OPTARG ;;
      g) GROUP=$OPTARG ;;
      s) START=$OPTARG ;;
      a) TAG=$OPTARG ;;
      x) PREFIX=$OPTARG ;;
      h|?|*) usage;;
   esac
done

CONFIG=configs/azure-$PROFILE.json

shift $(($OPTIND-1))

ACTION=$@
if [ -z $ACTION ]; then
   usage
fi

if ! is_valid_region $REGION ; then
   usage "Unsupported region '$REGION'"
fi

if [[ ! -z $ACTION && ! -z $DRYRUN ]]; then
   echo '***********************************'
   echo "Please use -G to do the real work"
   echo '***********************************'
fi

mkdir -p logs

case $ACTION in
   list)
      do_list_instance ;;
   launch)
      do_launch_instance ;;
   terminate)
      do_terminate_instance ;;
   *)
      usage "Invalid/missing Action '$ACTION'" ;;
esac
