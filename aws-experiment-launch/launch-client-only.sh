#!/usr/bin/env bash

TAG=${WHOAMI:-$USER}

INSTANCE=${1:-r5.xlarge}
REGIONS=${2:-1}
NUM_VM=${3:-1}

./create_solider_instances.py \
--regions $REGIONS \
--instances $NUM_VM \
--instancetype $INSTANCE \
--profile harmony-ec2 \
--tag ${TAG}-powerclient \
--userdata configs/userdata-soldier-http.sh \
--instance_output instance_output-client.txt \
--instance_ids_output instance_ids_output-client.txt

./collect_public_ips.py \
--profile harmony-ec2 \
--instance_output instance_output-client.txt \
--file_output raw_ip-client.txt
