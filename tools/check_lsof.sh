#!/usr/bin/env bash

# This script is used to check the open files on the node
#
# [Release]
# make lsof_release
#
# [Usage]
# bash <(curl -sSL https://haochen-harmony-pub.s3.amazonaws.com/pub/check_lsof/install.sh)

usage() {
   cat <<-EOU
bash <(curl -sSL https://haochen-harmony-pub.s3.amazonaws.com/pub/check_lsof/install.sh)

EOU
   exit 1
}

case "$1" in
   "-h"|"-H"|"-?"|"--help")
      usage;;
esac

NOW=$(date +%F.%T)
lsof_log="latest/lsof.${NOW}.log"
p2p_log="latest/p2p.${NOW}.log"
syncing_log="latest/syncing.${NOW}.log"

sudo lsof -np "$(pgrep harmony)" > "${lsof_log}"

grep cslistener "${lsof_log}" | awk -F'[:>]' ' { print $3 }' | sort -u > "${p2p_log}"
grep x11 "${lsof_log}" | awk -F'[:>]' ' { print $3 }' | sort -u > "${syncing_log}"

sleep 1
sync

/usr/bin/wc -l latest/{lsof,p2p,syncing}.${NOW}.log

rm -f latest/{lsof,p2p,syncing}.${NOW}.log
