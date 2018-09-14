#!/bin/bash

IP=$(curl http://169.254.169.254/2018-03-28/meta-data/public-ipv4)

BUCKET=unique-bucket-bin
FOLDER=ec2-user

sudo ./commander -ip $IP -mode s3 -config_url http://${BUCKET}.s3.amazonaws.com/${FOLDER}/distribution_config.txt
