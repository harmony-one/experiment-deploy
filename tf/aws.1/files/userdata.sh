#!/bin/bash

sudo yum update -y
sudo yum install -y bind-utils
sudo yum install -y jq

curl https://rclone.org/install.sh | sudo bash

mkdir -p /home/ec2-user/.hmy
mkdir -p /home/ec2-user/.config/rclone

chown -R ec2-user .hmy
chown -R ec2-user .config
