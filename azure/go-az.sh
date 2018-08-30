#!/bin/bash

set -euo pipefail

source ./common.sh

DRYRUN=
# use 10 resource group, can launch up to 800*10=8000 vms in one region

function usage
{
   ME=$(basename $0)
   cat<<EOF

Usage: $ME [ACTION] NUM_VMS

ACTION:
   init        init Azure regions (${REGIONS[@]})
   launch      launch vms in Azure region
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
      ./region.sh -r $region -s bh -g $MAX_NUM_RG -G init &
   done
   date

# wait for all resource groups created
   wait
   date
   for region in ${REGIONS[@]}; do
      ./region.sh -r $region list
      ./region.sh -r $region output
   done
   date
}

function launch_vms
{
   vm_per_rg=$(( $NUM_VMS / $MAX_NUM_RG ))
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
      ./instances.sh -r $region -s 99 -c $vm_per_group -g $group launch &
   done
   date

# wait for all instance launched
   wait
}

function list_ips
{
   date
   for region in ${REGIONS[@]}; do
      ./instances.sh -r $region -G listip > configs/$region.ips
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

#########################

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
   "deinit") deinit_region ;;
   "listip") list_ips ;;
   *) usage ;;
esac


