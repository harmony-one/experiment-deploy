#!/bin/bash

yum install ruby -y
cd /home/ec2-user/

BUCKET=unique-bucket-bin
FOLDER=

TESTBIN=( txgen soldier benchmark commander go-commander.sh )

for bin in "${TESTBIN[@]}"; do
   curl http://${BUCKET}.s3.amazonaws.com/${FOLDER}${bin} -o ${bin}
   chmod +x ${bin}
done

echo "* soft     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "* hard     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "* soft     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "* hard     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "root soft     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "root hard     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "root soft     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "root hard     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "session required pam_limits.so" | sudo tee -a /etc/pam.d/common-session

# Get My IP
ip=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)

NODE_PORT=9000
SOLDIER_PORT=1$NODE_PORT

# Kill existing soldier/node
fuser -k -n tcp $SOLDIER_PORT
fuser -k -n tcp $NODE_PORT

# Run soldier
./soldier -ip $ip -port $NODE_PORT > soldier_log 2>&1 &
