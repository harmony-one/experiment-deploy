#!/bin/bash

mkdir -p /home/ec2-user
cd /home/ec2-user

BUCKET=unique-bucket-bin
FOLDER=leo/

TESTBIN=( txgen soldier harmony libbls384.so libmcl.so wallet beat_tx_node.sh db.tgz )

for bin in "${TESTBIN[@]}"; do
   curl http://${BUCKET}.s3.amazonaws.com/${FOLDER}${bin} -o ${bin}
   chmod +x ${bin}
done

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

function restore_db {
   local dbdir=db/harmony_${PUB_IP}_${NODE_PORT}

   mkdir -p $dbdir
   [ -e db.tgz ] && tar xfz db.tgz -C $dbdir && rm -f db.tgz
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

   setup_metricbeat

fi

NODE_PORT=9000
SOLDIER_PORT=1$NODE_PORT

# Kill existing soldier/node
fuser -k -n tcp $SOLDIER_PORT
fuser -k -n tcp $NODE_PORT

# restore blockchain db
restore_db

# Run soldier
./soldier -ip $PUB_IP -port $NODE_PORT > soldier-${PUB_IP}.log 2>&1 &
