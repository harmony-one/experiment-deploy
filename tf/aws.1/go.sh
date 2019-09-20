#!/bin/bash

source ./regions.sh
OUTPUT=launch.ip
rm -f $OUTPUT

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
   IP=$(terraform output | jq -rc '.public_ip.value  | @tsv')
   echo "$IP" >> $OUTPUT
   sleep 1
   mv -f terraform.tfstate states/terraform.tfstate.$index
}

# _launch_many

INDEX=$*

for index in ${INDEX}; do
   do_launch_one $index
done

aws --profile mainnet s3 sync states/ s3://mainnet.log/states/

# fast sync
# pssh -l ec-user -h $OUTPUT -e fast/err -o fast/log 'nohup /home/ec2-user/fast.sh > fast.log 2> fast.err < /dev/null &'


# 455 539
