#!/usr/bin/env bash

# this script is used to rollback harmony binary/script for deployment
# it should be run on either mainnet or testnet devop hosts

set -eu

NETWORK=upgrade
NUM_VER=4
BUCKET=s3://pub.harmony.one/release/linux-x86_64
VERSION=

usage() {
   ME=$(basename "$0")
   cat<<-EOU
Usage: $ME [Options] [Actions]

Options:
   -h             print this help
   -N network     specify network type (upgrade, mainnet, lrtn)
                  (default: $NETWORK)
   -v version     specify the version to rollback
   -n num         specify number of version to list
                  (default: $NUM_VER)

Actions:
   list           list all previous version
   rollback       rollback to the version specified in -v

EOU
   exit 0
}

list_versions() {
   aws s3 ls "${BUCKET}/" | grep PRE | awk -F' ' ' { print $2 } ' | grep ^v | tail -n ${NUM_VER} | tr -d /
}

rollback_release() {
   if [ -z "${VERSION}" ]; then
      echo "Please specify the rollback version."
      return
   fi
   read -p "rollback \"${NETWORK}\" to \"${VERSION}\"? (y/n) " yesno
   case "$yesno" in
      y|Y) aws s3 cp "${BUCKET}/${VERSION}/static/" "${BUCKET}/${NETWORK}/static/" --recursive --acl public-read ;;
      *) echo bye... ;;
   esac
}

while getopts ":hN:n:v:" opt; do
   case "$opt" in
      h) usage ;;
      N) NETWORK="${OPTARG}" ;;
      n) NUM_VER="${OPTARG}" ;;
      v) VERSION="${OPTARG}" ;;
      *) usage ;;
   esac
done

shift $(( OPTIND - 1 ))

ACTION=${1:-usage}

case "${ACTION}" in
   list) list_versions ;;
   rollback) rollback_release ;;
   *) usage ;;
esac

# vim: set expandtab ts=2
