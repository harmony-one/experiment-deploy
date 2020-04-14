# This script is used to install node_exporter on any nodes using systemd service.
# Noted the port 9100 has to be open to your prometheus server.
#
# [Release]
# aws s3 cp install-node_exporter.sh s3://haochen-harmony-pub/pub/node_exporter/install.sh --acl public-read
#
# [Usage]
# bash <(curl -s -S -L https://haochen-harmony-pub.s3.amazonaws.com/pub/node_exporter/install.sh)

if pgrep node_exporter; then
   echo node_exporter is running, exiting ...
   exit
fi

NE=node_exporter-0.18.1.linux-amd64

curl -LO https://github.com/prometheus/node_exporter/releases/download/v0.18.1/${NE}.tar.gz
tar xfz ${NE}.tar.gz

sudo mv -f ${NE}/node_exporter /usr/local/bin
sudo useradd -rs /bin/false node_exporter
rm -f ${NE}.tar.gz
rm -rf ${NE}

curl -LO https://haochen-harmony-pub.s3.amazonaws.com/pub/node_exporter/node_exporter.service
sudo mv -f node_exporter.service /lib/systemd/system/node_exporter.service

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
