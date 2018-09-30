#!/usr/bin/env bash

TAG=${WHOAMI:-USER}

INSTANCE=${1:-r5.large}
REGIONS=${2:-1,2,3,4,5,6,7,8}
NUM=${3:-3,3,3,3,3,3,3,4}

./create_solider_instances.py \
--regions $REGIONS \
--instances $NUM \
--instancetype $INSTANCE \
--profile harmony-ec2 \
--tag ${TAG}-powerleader \
--userdata configs/userdata-soldier-http.sh \
--instance_output instance_output-leaders.txt \
--instance_ids_output instance_ids_output-leaders.txt

./collect_public_ips.py \
--profile harmony-ec2 \
--instance_output instance_output-leaders.txt \
--file_output raw_ip-leaders.txt
