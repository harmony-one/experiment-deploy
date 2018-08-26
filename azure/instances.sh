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


Action:
   list           list the vm launched
   launch         do deployment to launch instances
   terminate      terminate instances
   initregion     init one region (rg, nsg, vnet)
   createrg       create resource group
   creatensg      create network security group
   createvnet     create vnet/subnet
   clear          clear all vm/disk/nic/ip in one region

Examples:
   $ME -r eastus list
   $ME -r eastus -t configs/vm-template-1.json launch
   $ME -r eastus -s 10 -c 100 -g 1 launch
   $ME -r eastus -a 201808-01 -G initregion

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
      RG=$($JQ " .$region | .rg " $CONFIG | tr -d \")
      echo launching vms in $region/$NUM/$NSG/$VNET
      echo

      END=$(( $START + $GROUP ))
      for s in $(seq $START $END); do
         echo az group deployment create --name "$region.deploy.$TS" --resource-group $RG --template-file "$TEMPLATE" --parameters @${parameters} count=$COUNT start=$s
         date
         $DRYRUN az group deployment create --subscription $SUBSCRIPTION --name "$region.deploy.$TS" --resource-group $RG --template-file "$TEMPLATE" --parameters @${parameters} count=$COUNT start=$s 2>>$ERRLOG >> $LOG
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
      RG=$($JQ " .$region | .rg " $CONFIG | tr -d \")

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
   for region in "${REGIONS[@]}"; do
      if [ -n "$REGION" ]; then
         # run on specificed region
         if [ "$region" != "$REGION" ]; then
            continue
         fi
      fi

      local parameters=configs/vm-parameters-$region.json
      RG=$($JQ " .$region | .rg " $CONFIG | tr -d \")

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
      $DRYRUN az group create --location $region --name hb-rg-$region-$TAG --subscription $SUBSCRIPTION | tee -a $LOG
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
      $DRYRUN az network nsg create --resource-group hb-rg-$region-$TAG --subscription $SUBSCRIPTION --location $region --name hb-nsg-$region | tee -a $LOG
      $DRYRUN az network nsg rule create --resource-group hb-rg-$region-$TAG --subscription $SUBSCRIPTION --nsg-name hb-nsg-$region --name AllowSSH --priority 300 --source-address-prefixes Any --destination-port-ranges 22 --access Allow --protocol Tcp --description "Allow SSH" | tee -a $LOG
      $DRYRUN az network nsg rule create --resource-group hb-rg-$region-$TAG --subscription $SUBSCRIPTION --nsg-name hb-nsg-$region --name AllowNode --priority 400 --source-address-prefixes Any --destination-port-ranges 9000 --access Allow --protocol Tcp --description "Allow Node Port" | tee -a $LOG
      $DRYRUN az network nsg rule create --resource-group hb-rg-$region-$TAG --subscription $SUBSCRIPTION --nsg-name hb-nsg-$region --name AllowSoldier --priority 500 --source-address-prefixes Any --destination-port-ranges 19000 --access Allow --protocol Tcp --description "Allow Soldier Port" | tee -a $LOG
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
      $DRYRUN az network vnet create --resource-group hb-rg-$region-$TAG --subscription $SUBSCRIPTION --location $region --name hb-vnet-$region --address-prefixes 10.10.0.0/16 --subnet-name default --subnet-prefix 10.10.0.0/16 | tee -a $LOG
      echo $(date) >> $LOG
   done

}

function do_clear_all_resources
{
#TODO: confirm before clear

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

      local parameters=configs/vm-parameters-$region.json
      RG=$($JQ " .$region | .rg " $CONFIG | tr -d \")

      declare -a nicID=( $(az network nic list --resource-group $RG --subscription $SUBSCRIPTION --query '[].id' -o tsv) )
      if [ "${nicID}x" != "x" ]; then
         $DRYRUN az network nic delete --no-wait --resource-group $RG --subscription $SUBSCRIPTION --ids "${nicID[@]}" | tee -a $LOG
      fi

      declare -a ipID=( $(az network public-ip list --resource-group $RG --subscription $SUBSCRIPTION --query '[].id' -o tsv) )
      if [ "${ipID}x" != "x" ]; then
         $DRYRUN az network public-ip delete --resource-group $RG --subscription $SUBSCRIPTION --ids "${ipID[@]}" | tee -a $LOG
      fi

      declare -a accID=( $(az storage account list --resource-group $RG --subscription $SUBSCRIPTION --query '[].id' -o tsv) )
      if [ "${accID}x" != "x" ]; then
         $DRYRUN az storage account delete --yes --resource-group $RG --subscription $SUBSCRIPTION --ids "${accID[@]}" | tee -a $LOG
      fi

      declare -a diskID=( $(az disk list --resource-group $RG --subscription $SUBSCRIPTION --query '[].id' -o tsv) )
      if [ "${diskID}x" != "x" ]; then
         $DRYRUN az disk delete --yes --no-wait --resource-group $RG --subscription $SUBSCRIPTION --ids "${diskID[@]}" | tee -a $LOG
      fi

      echo $(date) >> $LOG
   done
   set -u
}

function do_init_region
{
   do_create_resourcegroup
   do_create_vnet
   do_create_nsg

   if [ "$DRYRUN" == "" ]; then
      sed -i.bak "s/hb-rg-$REGION-*/hb-rg-$REGION-$TAG/" $CONFIG
   else
      echo sed -i.bak "s/hb-rg-$REGION-*/hb-rg-$REGION-$TAG/" $CONFIG
   fi
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

while getopts "hnGr:p:t:v:c:g:s:a:" option; do
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
      h|?|*) usage;;
   esac
done

CONFIG=configs/azure-$PROFILE.json

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
   initregion)
      do_init_region ;;
   *)
      usage ;;
esac
