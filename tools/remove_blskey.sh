#!/usr/bin/env bash

HARMONYGO=harmony.go
HARMONYDB=https://raw.githubusercontent.com/harmony-one/harmony/main/internal/genesis/${HARMONYGO}

# This script is used to remove extra blskeys on harmony internal nodes
# This script requires jq package, will install them automatically
#
# [Release]
# aws s3 cp remove_blskey.sh s3://haochen-harmony-pub/pub/keyclean/install.sh --acl public-read
# ||
# make removekey_release
#
# [Usage]
# curl -sSfL https://haochen-harmony-pub.s3.amazonaws.com/pub/keyclean/install.sh | bash
#
# curl -sSfL https://haochen-harmony-pub.s3.amazonaws.com/pub/keyclean/install.sh | bash -s 90

usage() {
   ME=$(basename "$0")
   cat <<-EOU
Usage: $ME MAX_SLOT
The script will remove unused blskeys/pass and restart harmony process.

MAX_SLOT: 130/90 (default: 130)

Example:
curl -sSfL https://haochen-harmony-pub.s3.amazonaws.com/pub/keyclean/install.sh | bash
curl -sSfL https://haochen-harmony-pub.s3.amazonaws.com/pub/keyclean/install.sh | bash -s 90

EOU
   exit 1
}

check_env() {
   if ! command -v jq > /dev/null; then
      echo "installing jq"
      curl -sSfL https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -o "$HOME/jq" || return $?
      chmod +x "$HOME/jq"
   fi
}

download_harmony_go() {
   curl -sSfLO ${HARMONYDB} || return $?
}

find_valid_blskey() {
   curl --connect-timeout 5 --max-time 10 --location -s --request POST "http://127.0.0.1:9500/" \
        --header 'Content-Type: application/json' \
        --data-raw '{
         "jsonrpc": "2.0",
         "method": "hmy_getNodeMetadata",
         "params": [ ],
         "id": 1
        }' | jq -r .result.blskey > metadata.json
}

remove_unused_keys() {
   mkdir -p .hmy/oldblskeys
   for i in {0..9}; do
      pk=$(jq -r .[$i] metadata.json)
      if [ "${pk}" != "null" ]; then
         index=$(grep -F "$pk" "$HARMONYGO" | grep -oE 'Index:."[[:space:]]*[0-9]+[[:space:]]*"' | grep -oE '[0-9]+')
         num=$(( index / 4 ))
         if [ "${num}" -ge "${MAX_SLOT}" ]; then
            echo "moving $index/$num/$pk"
            mv -f .hmy/blskeys/"${pk}".* .hmy/oldblskeys
         fi
      fi
   done
}

restart_harmony() {
   if systemctl list-unit-files harmony.service | grep -q enabled; then
      sudo systemctl restart harmony || return $?
   else
      echo "WARN: can only restart harmony service using systemd"
      echo "please manually restart harmony process"
   fi
}

case "$1" in
   "-h"|"-H"|"-?"|"--help")
      usage;;
esac

MAX_SLOT=${1:-130}
case "$MAX_SLOT" in
   130|90) ;;
   *) usage ;;
esac

check_env || exit 2

if ! download_harmony_go; then
   echo "Failed to download harmony.go: ${HARMONYDB}"
   exit 3
fi

find_valid_blskey

remove_unused_keys || exit 6

# restart_harmony || exit 7

# rm -rf metadata.json ${HARMONYGO}
