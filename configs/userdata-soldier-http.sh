#!/bin/bash

# ------------------------------------------------------------------
# 
# VERSION:
# [1] Created by Leo Chen, Date: Unknown
# 		* created the initial script 
# [2] Modified by Andy Wu, Date: May 27, 2019
#		* created function setup_node_exporter
# [3] Modified by Andy Wu, Date: Jun 1, 2019
#   * removed mac implementation for node exporter deployment, plus code refactor
#   * fixed a code conflict issue
# 
# ------------------------------------------------------------------


mkdir -p /home/ec2-user
cd /home/ec2-user

BUCKET=unique-bucket-bin
FOLDER=leo/

TESTBIN=( soldier harmony libbls384_256.so libmcl.so )

for bin in "${TESTBIN[@]}"; do
   curl http://${BUCKET}.s3.amazonaws.com/${FOLDER}${bin} -o ${bin}
   chmod +x ${bin}
done

# Download the blspass file
aws s3 cp s3://harmony-pass/blspass.txt blspass.txt

export LD_LIBRARY_PATH=/home/ec2-user

sysctl -w net.core.somaxconn=1024
sysctl -w net.core.netdev_max_backlog=65536
sysctl -w net.ipv4.tcp_tw_reuse=1
sysctl -w net.ipv4.tcp_rmem='4096 65536 16777216'
sysctl -w net.ipv4.tcp_wmem='4096 65536 16777216'
sysctl -w net.ipv4.tcp_mem='65536 131072 262144'

echo "* soft     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "* hard     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "* soft     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "* hard     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "root soft     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "root hard     nproc          65535" | sudo tee -a /etc/security/limits.conf
echo "root soft     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "root hard     nofile         65535" | sudo tee -a /etc/security/limits.conf
echo "session required pam_limits.so" | sudo tee -a /etc/pam.d/common-session

get_es_endpoint() {
   # TODO ek: Make this work with a public (non-VPC) endpoint.
   ${AWS} es describe-elasticsearch-domain --domain-name="${1-"${ES_DOMAIN}"}" | \
      jq -r .DomainStatus.Endpoints.vpc | \
      grep .
   # grep . makes this function return failure if empty, i.e. domain not found.
}

setup_metricbeat() {
   (
      set -eu

      # Abort if the domain is not up and running in this region.
      : ${ES_DOMAIN=harmony}
      ES_ENDPOINT=$(get_es_endpoint) || exit $?
      # "null" endpoint means the domain exists but is not fully up and running.
      case "${ES_ENDPOINT}" in null) exit 1;; esac

      # Install Metricbeat.
      rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
      mkdir -p /etc/yum.repos.d
      # Another yum process may read from the incomplete repo file being written.
      # Avoid by first writing to a file with an extension yum ignores,
      # then moving the finished file under the proper name.
      cat > /etc/yum.repos.d/elastic-6.x.repo-wip << ENDEND
[elastic-6.x]
name=Elastic repository for 6.x packages
baseurl=https://artifacts.elastic.co/packages/6.x/yum
baseurl=https://artifacts.elastic.co/packages/6.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
ENDEND
      mv /etc/yum.repos.d/elastic-6.x.repo-wip /etc/yum.repos.d/elastic-6.x.repo
      yum -y install metricbeat

      # Configure Metricbeat
      # TODO ek: Query instance tags and add them, so as to help search.
      cat > /etc/metricbeat/metricbeat.yml <<- ENDEND
metricbeat.config.modules:
  path: \${path.config}/modules.d/*.yml
output.elasticsearch:
  hosts: ["${ES_ENDPOINT}:443"]
  protocol: "https"
processors:
  - add_host_metadata: ~
  - add_cloud_metadata: ~
setup.kibana:
  host: "${ES_ENDPOINT}:443"
  protocol: "https"
  path: "/_plugin/kibana"
ENDEND
      systemctl enable metricbeat
      systemctl start metricbeat
   )
}

setup_node_exporter() {
	set -eu
	OS=$(uname -s)
	os=$(echo "$OS" | awk '{print tolower($0)}')

	# node_exporter version: 0.18.0/2019-05-09
	URL_node_exporter_linux=https://github.com/prometheus/node_exporter/releases/download/v0.18.0/node_exporter-0.18.0.linux-amd64.tar.gz

   # download and decompress the node exporter in the tmp folder
	pushd /tmp
	curl -LO $URL_node_exporter_linux
   tar -xvf /tmp/node_exporter-0.18.0.$os-amd64.tar.gz
   # add a servcie account for node_exporter
	useradd -rs /bin/false node_exporter

	# move the node export binary to /usr/local/bin
	mv -f /tmp/node_exporter-0.18.0.$os-amd64/node_exporter /usr/local/bin/

	# create a node_exporter service file under systemd
	node_exporter_service=/etc/systemd/system/node_exporter.service # Linux only
   echo "[Unit]
   Description=Node Exporter
   After=network.target

   [Service]
   User=node_exporter
   Group=node_exporter
   Type=simple
   ExecStart=/usr/local/bin/node_exporter

   [Install]
   WantedBy=multi-user.target" > $node_exporter_service

	systemctl daemon-reload
	systemctl start node_exporter

	#enable the node exporter servie to the system startup
	systemctl enable node_exporter

   popd
}

function restore_db {
   local dbdir=db/harmony_${PUB_IP}_${NODE_PORT}

   mkdir -p $dbdir
   if [ -e db.tgz ]; then
      if file db.tgz | grep gzip ; then
         tar xfz db.tgz -C $dbdir && rm -f db.tgz
      fi
   fi
}

function restore_key {
   if [ -e hmykey.tgz ]; then
      if file hmykey.tgz | grep gzip ; then
         tar xfz hmykey.tgz && rm hmykey.tgz
      fi
   fi
   if [ -e hmykey2.tgz ]; then
      if file hmykey2.tgz | grep gzip ; then
         tar xfz hmykey2.tgz && rm hmykey2.tgz
      fi
   fi
}

IS_AWS=$(curl -s -I http://169.254.169.254/latest/meta-data/instance-type -o /dev/null -w "%{http_code}")
if [ "$IS_AWS" != "200" ]; then
# NOT AWS, Assuming Azure
   PUB_IP=$(curl -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2017-04-02&format=text")
else
   yum -y install jq
   PUB_IP=$(curl -sL http://169.254.169.254/latest/meta-data/public-ipv4)
   REGION=$(curl -sL http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
   mkdir -p ~/.aws
   cat << ENDEND >> ~/.aws/config
[profile default]
credential_source = Ec2InstanceMetadata
ENDEND
   AWS="aws --region=${REGION}"
   # use AWS time sync service
   # https://aws.amazon.com/blogs/aws/keeping-time-with-amazon-time-sync-service/
   yum -y erase ntp*
   yum -y install chrony
   service chronyd start

   # install dependencies of BLS
   yum -y install libstdc++ libgcc zlib openssl gmp

#   setup_metricbeat

fi

NODE_PORT=9000
SOLDIER_PORT=1$NODE_PORT

# Kill existing soldier/node
fuser -k -n tcp $SOLDIER_PORT
fuser -k -n tcp $NODE_PORT

# restore blockchain db
# restore_db

# restore key of hmy test node
# restore_key

# deploy node exporter
setup_node_exporter

# Run soldier
./soldier -ip $PUB_IP -port $NODE_PORT > soldier-${PUB_IP}.log 2>&1 &


function install_docker {
   # https://docs.docker.com/install/linux/docker-ce/centos/
   sudo yum remove -y docker \
                     docker-client \
                     docker-client-latest \
                     docker-common \
                     docker-latest \
                     docker-latest-logrotate \
                     docker-logrotate \
                     docker-engine


   sudo yum install -y yum-utils \
      device-mapper-persistent-data \
      lvm2

   sudo yum-config-manager \
      --add-repo \
      https://download.docker.com/linux/centos/docker-ce.repo

   sudo yum install -y containerd.io docker-ce-18.09.1 docker-ce-cli-18.09.1
   
   sudo systemctl enable docker.service
   sudo systemctl start docker
   sudo usermod -aG docker ec2-user

   sudo modprobe iptable_nat

   # persistent
   cat > /etc/sysconfig/modules/dockerd.modules <<- ENDEND
#!/bin/sh

exec /sbin/modprobe iptable_nat >/dev/null 2>&1
ENDEND

   sudo chmod +x /etc/sysconfig/modules/dockerd.modules

   # https://docs.docker.com/compose/install/
   sudo curl -L "https://github.com/docker/compose/releases/download/1.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
   sudo chmod +x /usr/local/bin/docker-compose
}

function download_map3 {
   mkdir map3
   curl https://static.hyn.space/deploy-map3/edge-dashboard/docker-compose.yml -o map3/docker-compose.yml
}

install_docker

download_map3

/usr/local/bin/docker-compose -f map3/docker-compose.yml up --detach
