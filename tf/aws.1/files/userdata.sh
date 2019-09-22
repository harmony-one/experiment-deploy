#!/bin/bash

sudo yum update -y
sudo yum install -y bind-utils
sudo yum install -y jq

curl https://rclone.org/install.sh | sudo bash
