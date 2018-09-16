#!/usr/bin/env bash

TAG=${WHOAMI:-USER}

./create_solider_instances.py \
--regions 1 \
--instances 1 \
--instancetype r5.2xlarge \
--profile harmony-ec2 \
--tag ${TAG}-powerclient \
--userdata configs/userdata-soldier-http.sh \
--instance_output instance_output-client.txt \
--instance_ids_output instance_ids_output-client.txt

./collect_public_ips.py \
--profile harmony-ec2 \
--instance_output instance_output-client.txt \
--file_output raw_ip-client.txt
