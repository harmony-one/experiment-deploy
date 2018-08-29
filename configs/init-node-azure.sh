#!/bin/bash

source /tmp/aws.config

PUB_IP=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2017-04-02&format=text")
TS=$(date +%y%m%d.%H%M%S)
NODEDIR=/tmp/nodes-$TS
SERVER=52.36.234.52

mkdir -p $NODEDIR
aws s3 cp s3://unique-bucket-bin/soldier $NODEDIR/soldier
aws s3 cp s3://unique-bucket-bin/benchmark $NODEDIR/benchmark
aws s3 cp s3://unique-bucket-bin/txgen $NODEDIR/txgen

chmod +x $NODEDIR/{soldier,benchmark,txgen}

cd $NODEDIR

node_port=9000
soldier_port=1$node_port
# Kill existing soldier
fuser -k -n tcp $soldier_port

# Run soldier
./soldier -ip $PUB_IP -port $node_port > soldier_log 2>&1 &
