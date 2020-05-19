#!/bin/bash

mkdir -p /home/ec2-user
cd /home/ec2-user

BUCKET=unique-bucket-bin
FOLDER=LRTN

TESTBIN=( harmony node.sh )

for bin in "${TESTBIN[@]}"; do
   curl http://${BUCKET}.s3.amazonaws.com/${FOLDER}/static/${bin} -o ${bin}
   chmod +x ${bin}
done

yum update -y
yum install -y bind-utils jq
# use AWS time sync service
# https://aws.amazon.com/blogs/aws/keeping-time-with-amazon-time-sync-service/
yum -y erase ntp*
yum -y install chrony
service chronyd start

# install rclone
curl https://rclone.org/install.sh | sudo bash

mkdir -p /home/ec2-user/.hmy/blskeys
mkdir -p /home/ec2-user/.config/rclone
mkdir -p /home/ec2-user/latest

# Download the blspass file
aws s3 cp s3://harmony-pass/blsnopass.txt bls.pass

chown -R ec2-user.ec2-user /home/ec2-user/*
chown -R ec2-user.ec2-user /home/ec2-user/.*

add_env() {
   filename=$1
   shift
   grep -qxF "$@" $filename || echo "$@" >> $filename
}

### KERNEL TUNING ###
# Increase size of file handles and inode cache
sysctl -w fs.file-max=2097152
# Do less swapping
sysctl -w vm.swappiness=10
sysctl -w vm.dirty_ratio=60
sysctl -w vm.dirty_background_ratio=2
# Sets the time before the kernel considers migrating a proccess to another core
sysctl -w kernel.sched_migration_cost_ns=5000000
### GENERAL NETWORK SECURITY OPTIONS ###
# Number of times SYNACKs for passive TCP connection.
sysctl -w net.ipv4.tcp_synack_retries=2
# Allowed local port range
sysctl -w net.ipv4.ip_local_port_range='2000 65535'
# Protect Against TCP Time-Wait
sysctl -w net.ipv4.tcp_rfc1337=1
# Control Syncookies
sysctl -w net.ipv4.tcp_syncookies=1
# Decrease the time default value for tcp_fin_timeout connection
sysctl -w net.ipv4.tcp_fin_timeout=15
# Decrease the time default value for connections to keep alive
sysctl -w net.ipv4.tcp_keepalive_time=300
sysctl -w net.ipv4.tcp_keepalive_probes=5
sysctl -w net.ipv4.tcp_keepalive_intvl=15
### TUNING NETWORK PERFORMANCE ###
# Default Socket Receive Buffer
sysctl -w net.core.rmem_default=31457280
# Maximum Socket Receive Buffer
sysctl -w net.core.rmem_max=33554432
# Default Socket Send Buffer
sysctl -w net.core.wmem_default=31457280
# Maximum Socket Send Buffer
sysctl -w net.core.wmem_max=33554432
# Increase number of incoming connections
sysctl -w net.core.somaxconn=8096
# Increase number of incoming connections backlog
sysctl -w net.core.netdev_max_backlog=65536
# Increase the maximum amount of option memory buffers
sysctl -w net.core.optmem_max=25165824
sysctl -w net.ipv4.tcp_max_syn_backlog=8192
# Increase the maximum total buffer-space allocatable
# This is measured in units of pages (4096 bytes)
sysctl -w net.ipv4.tcp_mem='786432 1048576 26777216'
sysctl -w net.ipv4.udp_mem='65536 131072 262144'
# Increase the read-buffer space allocatable
sysctl -w net.ipv4.tcp_rmem='8192 87380 33554432'
sysctl -w net.ipv4.udp_rmem_min=16384
# Increase the write-buffer-space allocatable
sysctl -w net.ipv4.tcp_wmem='8192 65536 33554432'
sysctl -w net.ipv4.udp_wmem_min=16384
# Increase the tcp-time-wait buckets pool size to prevent simple DOS attacks
sysctl -w net.ipv4.tcp_max_tw_buckets=1440000
sysctl -w net.ipv4.tcp_tw_reuse=1
sysctl -w net.ipv4.tcp_fastopen=3
sysctl -w net.ipv4.tcp_window_scaling=1

add_env /etc/security/limits.conf "* soft     nproc          65535"
add_env /etc/security/limits.conf "* hard     nproc          65535"
add_env /etc/security/limits.conf "* soft     nofile         65535"
add_env /etc/security/limits.conf "* hard     nofile         65535"
add_env /etc/security/limits.conf "root soft     nproc          65535"
add_env /etc/security/limits.conf "root hard     nproc          65535"
add_env /etc/security/limits.conf "root soft     nofile         65535"
add_env /etc/security/limits.conf "root hard     nofile         65535"
add_env /etc/pam.d/common-session "session required pam_limits.so"

setup_node_exporter() {
	URL_node_exporter_linux=https://github.com/prometheus/node_exporter/releases/download/v0.18.1/node_exporter-0.18.1.linux-amd64.tar.gz

   # download and decompress the node exporter in the tmp folder
	pushd /tmp
	curl -LO $URL_node_exporter_linux
   tar -xvf /tmp/node_exporter-0.18.1.linux-amd64.tar.gz
   # add a servcie account for node_exporter
	useradd -rs /bin/false node_exporter

	# move the node export binary to /usr/local/bin
	mv -f /tmp/node_exporter-0.18.1.linux-amd64/node_exporter /usr/local/bin/
   rm -rf /tmp/node_exporter-0.18.1.linux-amd64.tar.gz node_exporter-0.18.1.linux-amd64

   echo "
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
" > /lib/systemd/system/node_exporter.service

	systemctl daemon-reload
	systemctl enable node_exporter
	systemctl start node_exporter

   popd
}

setup_harmony_service() {

   echo '
[Unit]
Description=harmony service
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=1
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/home/ec2-user/node.sh -N testnet -1 -S -P -p /home/ec2-user/bls.pass -M -D
StandardError=syslog
SyslogIdentifier=harmony
StartLimitInterval=0
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
' > /lib/systemd/system/harmony.service

   systemctl daemon-reload
   systemctl enable harmony.service
#   systemctl start harmony.service
}

# deploy node exporter
setup_node_exporter

# start harmony service
setup_harmony_service
