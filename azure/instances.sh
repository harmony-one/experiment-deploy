#!/bin/bash

set -euo pipefail

source ./common.sh

function usage
{
   ME=$(basename $0)
   cat<<EOF

Usage: $ME [Options] ACTION

This script is used to manage instances in Azure

Options:
   -h          print this help message
   -n          dryrun mode (default)
   -G          do the real work
   -r region   run in region (supported regions: ${REGIONS[@]})
   -p profile  use profile config file

Action:
   list        list the vm launched
   launch      launch instances
   terminate   terminate instances

Examples:
   $ME -r eastus list

EOF

   exit 0
}

function do_launch_instance
{
   local config=configs/azure-$PROFILE.json
   mkdir -p logs

   for region in "${REGIONS[@]}"; do
      if [ -n "$REGION" ]; then
         # run on specificed region
         if [ "$region" != "$REGION" ]; then
            continue
         fi
      fi

      LOG=logs/$region.launch.$TS.log
      echo > $LOG

      local template=configs/vm-template.json
      local parameters=configs/vm-parameters.json

      NUM=$($JQ " .$region | .instancecount " $config)
      TYPE=$($JQ " .$region | .instancetype" $config)
      NSG=$($JQ " .$region | .nsg " $config)
      VNET=$($JQ " .$region | .vnet " $config)
      KEY=$($JQ " .$region | .pubkey " $config)
      echo launching vms in $region/$NUM/$TYPE/$NSG/$VNET
      echo

      $DRYRUN az group deployment create --name "$region.deploy.$TS" --resource-group "$RG" --template-file "$template" --parameters "@${parameters}"

# create vm one by one, this can be used as a fallback mechanism
#   for i in $(seq 1 $NUM); do
#      node="node${region}${i}"
#      az vm create --subscription "$SUBSCRIPTION"  --resource-group "$RG" --name $node --nsg $NSG --subnet default --vnet-name $VNET --ssh-key-value $KEY --public-ip-address ${node}_ip --size $TYPE --image UbuntuLTS | tee -a $LOG
#   done

      echo
   done
}

function do_list_instance
{
   mkdir -p logs

   for region in "${REGIONS[@]}"; do
      if [ -n "$REGION" ]; then
         # run on specificed region
         if [ "$region" != "$REGION" ]; then
            continue
         fi
      fi

      LOG=logs/$region.list.$TS.log
      echo > $LOG

      if [ -n "$DRYRUN" ]; then
         echo az vm list --resource-group $RG --subscription $SUBSCRIPTION --show-details --query '[].{name:name, ip:publicIps, size:hardwareProfile.vmSize}' -o tsv
      else
         az vm list --resource-group $RG --subscription $SUBSCRIPTION --show-details --query  '[].{name:name, ip:publicIps, size:hardwareProfile.vmSize}' -o tsv | tee -a $LOG
      fi

   done
}

function do_terminate_instance
{
   mkdir -p logs

   for region in "${REGIONS[@]}"; do
      if [ -n "$REGION" ]; then
         # run on specificed region
         if [ "$region" != "$REGION" ]; then
            continue
         fi
      fi

      LOG=logs/$region.delete.$TS.log
      echo > $LOG

      ID=( $(az vm list --resource-group $RG --subscription $SUBSCRIPTION --query '[].id' -o tsv) )
      if [ -n "$DRYRUN" ]; then
         echo az vm delete --yes --no-wait --resource-group $RG --subscription $SUBSCRIPTION --ids "${ID[@]}"
      else
         az vm delete --yes --no-wait --resource-group $RG --subscription $SUBSCRIPTION --ids "${ID[@]}" | tee -a $LOG
      fi

   done

}

######################################################

DRYRUN=echo
TS=$(date +%Y%m%d.%H%M%S)
REGION=
PROFILE=small

while getopts "hnGr:p:" option; do
   case $option in
      r) REGION=$OPTARG ;;
      G) DRYRUN= ;;
      p) PROFILE=$OPTARG ;;
      h|?|*) usage;;
   esac
done

shift $(($OPTIND-1))

ACTION=$@

if [[ ! -z $ACTION && ! -z $DRYRUN ]]; then
   echo '***********************************'
   echo "Please use -G to do the real work"
   echo '***********************************'
fi

case $ACTION in
   list)
      do_list_instance ;;
   launch)
      do_launch_instance ;;
   terminate)
      do_terminate_instance ;;
   *)
      usage ;;
esac
