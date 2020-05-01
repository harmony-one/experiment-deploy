#!/usr/bin/env bash

# install node_exporter
set -eu
OS=$(uname -s)
os=$(echo "$OS" | awk '{print tolower($0)}')

# node_exporter version: 0.18.1/2019-06-04
URL_node_exporter_linux=https://github.com/prometheus/node_exporter/releases/download/v0.18.1/node_exporter-0.18.1.linux-amd64.tar.gz

# download and decompress the node exporter in the tmp folder
echo "downloading node_exporter ..."
curl -LO $URL_node_exporter_linux
tar -xvf node_exporter-0.18.1.$os-amd64.tar.gz
# add a servcie account for node_exporter
echo "adding user node_exporter ..."
id -u node_exporter &>/dev/null || sudo useradd -rs /bin/false node_exporter


# move the node export binary to /usr/local/bin
echo "moving files into /usr/local/bin/ folder ..."
mv -f node_exporter-0.18.1.$os-amd64/node_exporter /usr/local/bin/

# create a node_exporter service file under systemd
node_exporter_service=/etc/systemd/system/node_exporter.service # Linux only
echo "creating node exporter service file ..."
echo "[Unit]
Description=Node Exporter
After=network.target
[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
[Install]
WantedBy=multi-user.target" >$node_exporter_service

# junk files clean up on home dir
rm -rf node_exporter-0.18.1.linux-amd64*