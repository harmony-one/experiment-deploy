#!/bin/bash

set -euo pipefail

source ./common.sh

SUFFIX=$(whoami)
# use 10 resource group, can launch up to 800*10=8000 vms in one region
GROUP=$MAX_NUM_RG

function usage
{
   ME=$(basename $0)
   cat<<EOF

Usage: $ME [OPTIONS] ACTION NUM_VMS

OPTIONS:
   -h          print this help message
   -s suffix   set suffix of resource groups (default: $SUFFIX)
   -g group    set the number of resource groups (default: $GROUP)

ACTION:
   init        init Azure regions (${REGIONS[@]})
   launch      launch vms in Azure region
   delete      delete all vms
   deinit      deinit Azure regions
   listip      list ip address of all instances

$MAX_NUM_RG <= NUM_VMS <= $MAX_VM_PER_REGION

EOF
   exit 1
}

function init_region
{
   date
   for region in ${REGIONS[@]}; do
      ./region.sh -r $region -s $SUFFIX -g $GROUP -G init &
   done

# wait for all resource groups created
   wait
   date

#   date
#   for region in ${REGIONS[@]}; do
#      ./region.sh -r $region list
#      ./region.sh -r $region output
#   done
#   date
}

function launch_vms
{
   vm_per_rg=$(( $NUM_VMS / $GROUP ))
   if [ $vm_per_rg -gt $MAX_PER_DEPLOY ]; then
      group=$(( $vm_per_rg / $MAX_PER_DEPLOY ))
      reminder=$(( $vm_per_rg % $MAX_PER_DEPLOY ))
      if [ $reminder -ge 1 ]; then
         group=$(( $group + 1 ))
      fi
      vm_per_group=$(( $vm_per_rg / $group ))
   else
      group=1
      vm_per_group=$vm_per_rg
   fi

# -s 99 is to set a tag, which is adjustable
# TODO: add a parameter to change the tag
   date
   for region in ${REGIONS[@]}; do
      ./instances.sh -r $region -s 99 -c $vm_per_group -g $group -G launch &
   done

# wait for all instance launched
   wait
   echo Instance launch in $region is done.
   date
}

function list_ips
{
   date
   rm -f configs/raw_ip.txt
   for region in ${REGIONS[@]}; do
      ./instances.sh -r $region -G listip > configs/$region.ips
      cat configs/$region.ips >> configs/raw_ip.txt
   done
   date
}

function delete_vms
{
   date
   for region in ${REGIONS[@]}; do
      ./instances.sh -r $region -G terminate
   done
   date
}

function deinit_region
{
   date
   for region in ${REGIONS[@]}; do
      ./region.sh -r $region list
      ./region.sh -r $region -y delete
   done
   date

   echo Please check back in 1 hour on the resource group in case they are not deleted
   echo using ./regin.sh -r REGION list
}

###############################
while getopts "hs:g:" option; do
   case $option in
      h) usage ;;
      s) SUFFIX=$OPTARG ;;
      g) GROUP=$OPTARG ;;
   esac
done

shift $(($OPTIND-1))

ACTION=${1:-help}
NUM_VMS=${2:-$MAX_NUM_RG}

if [ $NUM_VMS -lt $MAX_NUM_RG ]; then
   NUM_VMS=$MAX_NUM_RG
fi

if [ $NUM_VMS -gt $MAX_VM_PER_REGION ]; then
   NUM_VMS=$MAX_VM_PER_REGION
   echo Can only launch up to $MAX_VM_PER_REGION VMs per region, set NUM_VMS to $MAX_VM_PER_REGION
fi

case "$ACTION" in
   "init") init_region ;;
   "launch") launch_vms ;;
   "delete") delete_vms ;;
   "deinit") deinit_region ;;
   "listip") list_ips ;;
   *) usage ;;
esac

# TODO: support one region, in case of failure
# TODO: handle failed deployment
# TODO: handle partial failure of the deployment
