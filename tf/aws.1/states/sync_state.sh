#!/bin/bash

AWS='aws --profile mainnet'
REPO=s3://mainnet.log/states

action=${1:-download}

function usage() {
   ME=$(basename $0)
   cat<<EOT
Usage:

$ME upload/download

   upload      upload/sync local terraform state to s3 bucket: $REPO 
   download    download/sync s3 bucket: $REPO to local terraform state

EOT
   exit 0
}

case $action in
   download)
      $AWS s3 sync $REPO .
      ;;
   upload)
      $AWS s3 sync . $REPO
      ;;
   *)
      usage
esac
