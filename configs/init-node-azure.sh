#!/bin/bash

PUB_IP=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2017-04-02&format=text")

# yum install ruby -y
mkdir -p /home/ec2-user
cd /home/ec2-user/

curl http://unique-bucket-bin.s3.amazonaws.com/txgen -o txgen
curl http://unique-bucket-bin.s3.amazonaws.com/soldier -o soldier
curl http://unique-bucket-bin.s3.amazonaws.com/benchmark -o benchmark
curl http://unique-bucket-bin.s3.amazonaws.com/commander -o commander
curl http://unique-bucket-bin.s3.amazonaws.com/go-commander.sh -o go-commander.sh
curl http://unique-bucket-bin.s3.amazonaws.com/kill_node.sh -o kill_node.sh

chmod +x ./soldier
chmod +x ./txgen
chmod +x ./commander
chmod +x ./kill_node.sh
chmod +x ./benchmark
chmod +x ./go-commander.sh

echo "* soft     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "* hard     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "* soft     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "* hard     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "root soft     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "root hard     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "root soft     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "root hard     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "session required pam_limits.so" | sudo tee -a /etc/pam.d/common-session

NODE_PORT=9000
SOLDIER_PORT=1$NODE_PORT

# Kill existing soldier/node
fuser -k -n tcp $SOLDIER_PORT
fuser -k -n tcp $NODE_PORT

# Run soldier
./soldier -ip $PUB_IP -port $NODE_PORT > soldier_log 2>&1 &
