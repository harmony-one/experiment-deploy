#!/usr/bin/env bash

GOOS=linux
GOARCH=amd64
env GOOS=$GOOS GOARCH=$GOARCH go build -o bin/soldier experiment/soldier/main.go
env GOOS=$GOOS GOARCH=$GOARCH go build -o bin/commander experiment/commander/main.go

AWSCLI=aws
if [ "$1" != "" ]; then
   AWSCLI+=" --profile $1"
fi

$AWSCLI s3 cp bin/soldier s3://unique-bucket-bin/soldier --acl public-read-write
$AWSCLI s3 cp bin/commander s3://unique-bucket-bin/commander --acl public-read-write
$AWSCLI s3 cp aws/kill_node.sh s3://unique-bucket-bin/kill_node.sh --acl public-read-write
$AWSCLI s3 cp aws/go-commander.sh s3://unique-bucket-bin/go-commander.sh --acl public-read-write
$AWSCLI s3 cp configs/init-node-azure.sh s3://haochen-harmony-pub/nodes/init-node-azure.sh --acl public-read
