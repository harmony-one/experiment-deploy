#!/bin/bash

source ./regions.sh

function _launch_many {
   local START=592
   local END=679

   for i in $(seq ${START} ${END}); do
#      mod=$(( i % 4 ))
#      if [ $mod == 3 ]; then
         do_launch_one $i
#      fi
   done
}

function do_launch_one {
   local index=$1

   if [ -z $index ]; then
      echo no index, exit
      return
   fi

   region=${REGIONS[$RANDOM % ${#REGIONS[@]}]}
   terraform apply -var "aws_region=$region" -var "blskey_index=$index" -auto-approve || exit
   sleep 1
   mv -f terraform.tfstate states/terraform.tfstate.$index
}

# _launch_many

INDEX=$*

for index in ${INDEX}; do
   do_launch_one $index
done

aws --profile mainnet s3 sync states/ s3://mainnet.log/states/

# 455 539
