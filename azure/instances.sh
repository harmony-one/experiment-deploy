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
   listip         list all the public ip
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
   LOG=logs/$region.launch.$TS.log
   ERRLOG=logs/$region.launch.error.$TS.log
   echo $(date) > $LOG
   echo $(date) > $ERRLOG

   for rg in ${RGS[@]}; do
      NUM=$($JQ ' .parameters.count.value ' $PARAMETERS)
      NSG=$(az network nsg list --resource-group $rg | $JQ .[].name)
      VNET=$(az network vnet list --resource-group $rg | $JQ .[].name)

      END=$(( $START + $GROUP - 1 ))
      (
      for s in $(seq $START $END); do
         date
         set -x
         $DRYRUN az group deployment create --name $region.deploy.$TS --resource-group $rg --template-file $TEMPLATE --parameters @${PARAMETERS} count=$COUNT start=$s harmony_benchmark_nsg=$NSG harmony_benchmark_vnet=$VNET 2>>$ERRLOG >> $LOG
         date
      done
      ) &
   done

   wait
   echo $(date) >> $LOG
   echo $(date) >> $ERRLOG
   echo
}

function do_list_instance
{
   LOG=logs/$region.list.$TS.log
   for rg in ${RGS[@]}; do
      if [ -n "$DRYRUN" ]; then
         echo az vm list --resource-group $rg --show-details --query '[].{ip:publicIps}' -o tsv
      else
         az vm list --resource-group $rg --show-details --query '[].{ip:publicIps}' -o tsv | tee -a $LOG
      fi
   done
}

function do_list_ip
{
   LOG=logs/$region.listip.$TS.log
   for rg in ${RGS[@]}; do
      if [ -n "$DRYRUN" ]; then
         echo az network public-ip list --resource-group $rg --query "[?provisioningState=='Succeeded']"
      else
      (
         set -x
         az network public-ip list --resource-group $rg --query "[?provisioningState=='Succeeded']" | $JQ .[].ipAddress | tee -a $LOG
      )
      fi
   done
}

function do_terminate_instance
{
   LOG=logs/$region.delete.$TS.log
   echo $(date) > $LOG
   for rg in ${RGS[@]}; do
      ID=( $(az vm list --resource-group $rg --query '[].id' -o tsv) )
      if [ -n "$DRYRUN" ]; then
         echo az vm delete --yes --no-wait --resource-group $rg --ids ${ID[@]+"${ID[@]}"}
      else
         if [ ${#ID[@]} -gt 0 ]; then
         (
            set -x
            az vm delete --yes --no-wait --resource-group $rg --ids ${ID[@]+"${ID[@]}"} | tee -a $LOG
         )
         fi
      fi
   done
   echo $(date) >> $LOG
}

function _check_configuration_files
{
   RGCONFIG=configs/$PROFILE.rg.$REGION.json
   if [ ! -f $RGCONFIG ]; then
      echo Could not find the resource group configuration file: $RGCONFIG
      exit 1
   else
      RGS=( $($JQ ' .[].name ' $RGCONFIG) )
   fi

   if [ ! -f $TEMPLATE ]; then
      echo Could not find the template file: $TEMPLATE
      exit 1
   fi

   PARAMETERS=configs/vm-parameters-$region.json
   if [ ! -f $PARAMETERS ]; then
      echo Could not find the parameters file: $PARAMETERS
      exit 1
   fi
}
######################################################

DRYRUN=echo
TS=$(date +%Y%m%d.%H%M%S)
TAG=$(date +%m%d)
REGION=
PROFILE=benchmark
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

shift $(($OPTIND-1))

ACTION=$@
if [ -z $ACTION ]; then
   usage
fi

if ! is_valid_region $REGION ; then
   usage "Unsupported region '$REGION'"
fi

_check_configuration_files

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
   listip)
      do_list_ip ;;
   *)
      usage "Invalid/missing Action '$ACTION'" ;;
esac
