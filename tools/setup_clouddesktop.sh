#!/bin/bash

REGION=us-west-1
AWS="aws --profile harmony-ec2 --region $REGION"
TODAY=$(date +%m-%d)
SCRIPT=mydesktop.sh

echo -n "Enter your Harmony email and press [ENTER]: "
read email

ALIAS=$(echo $email | cut -f 1 -d@)

echo launching instance ..
i_id=$($AWS ec2 run-instances \
--launch-template LaunchTemplateId=lt-0490d5a13c3534767 \
--count=1 \
--disable-api-termination \
--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$ALIAS-DevDesktop-$TODAY}]" \
--user-data "sed -i 's/export WHOAMI=.*/export WHOAMI=$ALIAS/' /home/ec2-user/.bashrc" \
--query ' Instances[0].InstanceId ' | tr -d \")

echo waiting for instance launch. sleeping 30s ..
sleep 30

$AWS ec2 associate-iam-instance-profile --instance-id $i_id --iam-instance-profile 'Name=harmony-ec2-s3-role'

i_ip=$($AWS ec2 describe-instances --instance-ids $i_id --query ' Reservations[0].Instances[0].PublicIpAddress ' | tr -d \")

ssh -i ~/.ssh/keys/california-key-benchmark.pem ec2-user@$i_ip "sed -i 's/export WHOAMI=.*/export WHOAMI=$ALIAS/' /home/ec2-user/.bashrc"

echo Please use $SCRIPT to login to your desktop.
echo "exec ssh -i ~/.ssh/keys/california-key-benchmark.pem ec2-user@$i_ip" > $SCRIPT
chmod +x $SCRIPT
