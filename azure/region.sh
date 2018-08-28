#!/bin/bash
set -euo pipefail
source ./common.sh

function usage
{
   ME=$(basename $0)
   MSG=${1:-''}

   cat<<EOF

Usage: $ME [Options] ACTION

This script is used to manage resource group, network security group
and vnet in Azure.

The script will be executed in dryrun mode by default.
You need to use -G to request the real execution of the commands.

Options:
   -h             print this help message
   -G             do the real work
   -r region      [MANDATORY] run in region (supported regions: ${REGIONS[@]})
   -g group       number of resource groups (default: $GROUP)
   -s start       the starting prefix of the resource group (default: $START)

   -p profile     the profile of the generated output file (default: $PROFILE)
   -t template    the resource template file (default: $TEMPLATE)
   -v parameter   the parameter file  (default: $PARAMETER)

   -a tag         tag of the resource group (default: $TAG)
   -y             no confirmation for the delete (default: $YESNO)


Action:
   list           list the resources
   init           do deployment to init a region
   delete         delete all resources in one region
   output         update profile to save the resource group data

Examples:
   $ME -r eastus list
   $ME -r eastus -s test -g 2 init
   $ME -r eastus delete

# the resource group will be named as: hb-rg-{REGION}-{TAG}-{START}{NUM}
Ex:
   hb-rg-eastus-$TAG-${START}1
   hb-rg-eastus-$TAG-${START}2
   hb-rg-eastus-$TAG-${START}3

----------------------------------
NOTE: $MSG
EOF

   exit 0
}

function do_init_region
{
   for i in $(seq 1 $GROUP); do
   (
      $DRYRUN ./deploy.sh -i $SUBSCRIPTION -g hb-rg-$REGION-$TAG-${START}$i -n bh-rg-$REGION-deployment -l $REGION -t $TEMPLATE -v $PARAMETER -p start=$START$i
   ) &
   done
   wait
   if [ -n "$DRYRUN" ]; then
      echo "NOTE: please use -G to do the real action"
   fi
}

function do_delete_region
{
   rgs=$(az group list --query "[?starts_with(name,'hb-rg-$REGION')]" | $JQ '.[].name')
   for i in ${rgs}; do
      if [ "$YESNO" != "yes" ]; then
         read -p "Do you want to remove resource group: $i (yes/no)?" yesno
      else
         yesno=yes
      fi
      if [ "$yesno" = "yes" ]; then
      (
         set -x
         az group delete --no-wait --yes --name $i
      )
      fi
   done
}

function do_list_resources
{
   az group list --query "[?starts_with(name,'hb-rg-$REGION')]" | $JQ '.[].name'
}

function do_save_output
{
   set -x
   az group list --query "[?starts_with(name,'hb-rg-$REGION')]" > configs/$PROFILE.rg.$REGION.json
}

######################################################

DRYRUN=echo
TS=$(date +%Y%m%d.%H%M%S)
TAG=$(date +%m%d)
REGION=
TEMPLATE=configs/vnet-template.json
PARAMETER=configs/vnet-parameters.json
PROFILE=benchmark
GROUP=1
START=100
YESNO=no

while getopts "hnGr:g:t:v:a:p:s:y" option; do
   case $option in
      r) REGION=$OPTARG ;;
      G) DRYRUN= ;;
      t) TEMPLATE=$OPTARG ;;
      v) PARAMETER=$OPTARG ;;
      g) GROUP=$OPTARG ;;
      a) TAG=$OPTARG ;;
      s) START=$OPTARG ;;
      y) YESNO=yes ;;
      h|?|*) usage ;;
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

mkdir -p logs
case $ACTION in
   list)
      do_list_resources ;;
   delete)
      do_delete_region ;;
   init)
      do_init_region ;;
   output)
      do_save_output ;;
   *)
      usage "Invalid/missing Action '$ACTION'" ;;
esac

