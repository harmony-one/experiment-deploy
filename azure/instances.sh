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
   createrg    create resource group
   creatensg   create network security group
   createvnet  create vnet/subnet
   clear       clear all vm/disk/nic/ip

Examples:
   $ME -r eastus list

EOF

   exit 0
}

function do_launch_instance
{
   local config=configs/azure-$PROFILE.json

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

      local template=configs/vm-template.json
      local parameters=configs/vm-parameters-$region.json

      NUM=$($JQ " .$region | .instancecount " $config)
      TYPE=$($JQ " .$region | .instancetype" $config)
      NSG=$($JQ " .$region | .nsg " $config)
      VNET=$($JQ " .$region | .vnet " $config)
      KEY=$($JQ " .$region | .pubkey " $config)
      RG=$($JQ " .$region | .resourcegroup " $config | tr -d \")
      echo launching vms in $region/$NUM/$TYPE/$NSG/$VNET
      echo

      $DRYRUN az group deployment create --name "$region.deploy.$TS" --resource-group $RG --template-file "$template" --parameters "@${parameters}" 2>>$ERRLOG | tee -a $LOG

      echo $(date) >> $LOG
      echo $(date) >> $ERRLOG

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
   local config=configs/azure-$PROFILE.json
   for region in "${REGIONS[@]}"; do
      if [ -n "$REGION" ]; then
         # run on specificed region
         if [ "$region" != "$REGION" ]; then
            continue
         fi
      fi

      RG=$($JQ " .$region | .resourcegroup " $config | tr -d \")

      if [ -n "$DRYRUN" ]; then
         echo az vm list --resource-group $RG --subscription $SUBSCRIPTION --show-details --query '[].{name:name, ip:publicIps, size:hardwareProfile.vmSize}' -o tsv
      else
         LOG=logs/$region.list.$TS.log
         echo $(date) > $LOG
         az vm list --resource-group $RG --subscription $SUBSCRIPTION --show-details --query  '[].{name:name, ip:publicIps, size:hardwareProfile.vmSize}' -o tsv | tee -a $LOG
         echo $(date) >> $LOG
      fi

   done
}

function do_terminate_instance
{
# TODO: confirm before terminate

   local config=configs/azure-$PROFILE.json
   for region in "${REGIONS[@]}"; do
      if [ -n "$REGION" ]; then
         # run on specificed region
         if [ "$region" != "$REGION" ]; then
            continue
         fi
      fi
      RG=$($JQ " .$region | .resourcegroup " $config | tr -d \")

      ID=( $(az vm list --resource-group $RG --subscription $SUBSCRIPTION --query '[].id' -o tsv) )
      if [ -n "$DRYRUN" ]; then
         echo az vm delete --yes --no-wait --resource-group $RG --subscription $SUBSCRIPTION --ids "${ID[@]}"
      else
         LOG=logs/$region.delete.$TS.log
         echo $(date) > $LOG
         az vm delete --yes --no-wait --resource-group $RG --subscription $SUBSCRIPTION --ids "${ID[@]}" | tee -a $LOG
         echo $(date) >> $LOG
      fi


   done
}

function do_create_resourcegroup
{

# TODO: delete existing one if it exists, confirmation is needed
   for region in "${REGIONS[@]}"; do
      if [ -n "$REGION" ]; then
         # run on specificed region
         if [ "$region" != "$REGION" ]; then
            continue
         fi
      fi

      LOG=logs/$region.rg.$TS.log
      echo $(date) > $LOG
      $DRYRUN az group create --location $region --name hb-rg-$region --subscription $SUBSCRIPTION | tee -a $LOG
      echo $(date) >> $LOG
   done

}

function do_create_nsg
{
   for region in "${REGIONS[@]}"; do
      if [ -n "$REGION" ]; then
         # run on specificed region
         if [ "$region" != "$REGION" ]; then
            continue
         fi
      fi
      LOG=logs/$region.nsg.$TS.log
      echo $(date) > $LOG
      $DRYRUN az network nsg create --resource-group hb-rg-$region --subscription $SUBSCRIPTION --location $region --name hb-nsg-$region | tee -a $LOG
      $DRYRUN az network nsg rule create --resource-group hb-rg-$region --subscription $SUBSCRIPTION --nsg-name hb-nsg-$region --name SSH --priority 300 --source-address-prefixes Internet --destination-port-ranges 22 --access Allow --protocol Tcp --description "Allow SSH" | tee -a $LOG
      echo $(date) >> $LOG

   done
}

function do_create_vnet
{
   for region in "${REGIONS[@]}"; do
      if [ -n "$REGION" ]; then
         # run on specificed region
         if [ "$region" != "$REGION" ]; then
            continue
         fi
      fi
      LOG=logs/$region.vnet.$TS.log
      echo $(date) > $LOG
      $DRYRUN az network vnet create --resource-group hb-rg-$region --subscription $SUBSCRIPTION --location $region --name hb-vnet-$region --address-prefixes 10.10.0.0/16 --subnet-name default --subnet-prefix 10.10.0.0/16 | tee -a $LOG
      echo $(date) >> $LOG
   done

}

function do_clear_all_resources
{
#TODO: confirm before clear

   local config=configs/azure-$PROFILE.json
   set +u
   for region in "${REGIONS[@]}"; do
      if [ -n "$REGION" ]; then
         # run on specificed region
         if [ "$region" != "$REGION" ]; then
            continue
         fi
      fi
      LOG=logs/$region.clear.$TS.log
      echo $(date) > $LOG
      RG=$($JQ " .$region | .resourcegroup " $config | tr -d \")

      declare -a nicID=( $(az network nic list --resource-group $RG --subscription $SUBSCRIPTION --query '[].id' -o tsv) )
      if [ "${nicID}x" != "x" ]; then
         $DRYRUN az network nic delete --resource-group $RG --subscription $SUBSCRIPTION --ids "${nicID[@]}" | tee -a $LOG
      fi

      declare -a ipID=( $(az network public-ip list --resource-group $RG --subscription $SUBSCRIPTION --query '[].id' -o tsv) )
      if [ "${ipID}x" != "x" ]; then
         $DRYRUN az network public-ip delete --resource-group $RG --subscription $SUBSCRIPTION --ids "${ipID[@]}" | tee -a $LOG
      fi

      declare -a accID=( $(az storage account list --resource-group $RG --subscription $SUBSCRIPTION --query '[].id' -o tsv) )
      if [ "${accID}x" != "x" ]; then
         $DRYRUN az storage account delete --yes --no-wait --resource-group $RG --subscription $SUBSCRIPTION --ids "${accID[@]}" | tee -a $LOG
      fi

      declare -a diskID=( $(az disk list --resource-group $RG --subscription $SUBSCRIPTION --query '[].id' -o tsv) )
      if [ "${diskID}x" != "x" ]; then
         $DRYRUN az disk delete --yes --no-wait --resource-group $RG --subscription $SUBSCRIPTION --ids "${diskID[@]}" | tee -a $LOG
      fi

      echo $(date) >> $LOG
   done
   set -u
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

mkdir -p logs

case $ACTION in
   createrg)
      do_create_resourcegroup ;;
   createvnet)
      do_create_vnet ;;
   creatensg)
      do_create_nsg ;;
   list)
      do_list_instance ;;
   launch)
      do_launch_instance ;;
   terminate)
      do_terminate_instance ;;
   clear)
      do_clear_all_resources ;;
   *)
      usage ;;
esac
