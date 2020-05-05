#!/usr/bin/env bash

TOOL_BUCKET=haochen-harmony-pub
KEYS=( bucket folder snapshot shard )
declare -A CONFIG_KV

# This script is used to install harmony_db_* snapshot into the node
# This script requires jq/rclone package, will install them automatically
# This script assumes the harmony_db_? directory is in the home directory on the node.
#
# [Release]
# aws s3 cp install-db_snapshot.sh s3://haochen-harmony-pub/pub/db_snapshot/install.sh --acl public-read
# aws s3 cp dryrun.snapshot.json s3://haochen-harmony-pub/pub/db_snapshot/default.json --acl public-read
# ||
# make snapshot_release
#
# [Usage]
# curl -sSfL https://haochen-harmony-pub.s3.amazonaws.com/pub/db_snapshot/install.sh | bash -s <config_json_file>
#
# [Examples]
# * install latest mainnet db snapshot, both sharding chain db and beacon chain db, using default.json
# curl -sSfL https://haochen-harmony-pub.s3.amazonaws.com/pub/db_snapshot/install.sh | bash
#
# * install specific mainnet db snapshot, shard 1 only
# curl -sSfL https://haochen-harmony-pub.s3.amazonaws.com/pub/db_snapshot/install.sh | bash -s mainnet.snapshot.json
#
# * install specific ostn db snapshot
# curl -sSfL https://haochen-harmony-pub.s3.amazonaws.com/pub/db_snapshot/install.sh | bash -s ostn.snapshot.json

usage() {
   ME=$(basename "$0")
   cat <<-EOU
Usage: $ME config_json_file

Default config is: default.json

All the configuration json files are in s3://${TOOL_BUCKET}/pub/db_snapshot/.

The script will stop harmony process, backup current DB, download latest/specific snapshot, restart harmony process.

EOU
   exit 1
}

check_env() {
   if ! command -v jq > /dev/null; then
      echo "installing jq"
      curl -sSfL https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -o "$HOME/jq" || return $?
      chmod +x "$HOME/jq"
   fi

   if ! command -v rclone > /dev/null; then
      echo "installing rclone"
      echo "curl https://rclone.org/install.sh | sudo bash"
      curl -sSfL https://rclone.org/install.sh | sudo bash
      mkdir -p ~/.config/rclone
   fi

   if ! grep -q 'hmy' ~/.config/rclone/rclone.conf 2> /dev/null; then
      echo "adding [hmy] profile to rclone.conf"
      cat <<-EOT >>~/.config/rclone/rclone.conf

[hmy]
type = s3
provider = AWS
env_auth = false
region = us-west-1
acl = public-read

EOT
   fi

}

download_config() {
   curl -sSfL "http://${TOOL_BUCKET}.s3.amazonaws.com/pub/db_snapshot/${CONFIGFILE}" -o "${CONFIGFILE}" || return $?
}

parse_config() {
   for key in "${KEYS[@]}"; do
      local value
      value=$(jq -r ".${key}" "${CONFIGFILE}")
      CONFIG_KV[$key]=$value
      echo "$key => ${CONFIG_KV[$key]}"
   done
}

_download_one_db() {
   for s in $(echo "$@" | tr " " "\n" | sort -u); do
      echo "rclone sync hmy://${CONFIG_KV[bucket]}/${CONFIG_KV[folder]}/${CONFIG_KV[snapshot]}/harmony_db_${s} harmony_db_${s}"
      rclone sync "hmy://${CONFIG_KV[bucket]}/${CONFIG_KV[folder]}/${CONFIG_KV[snapshot]}/harmony_db_${s}" "harmony_db_${s}" || return $?
   done
   return 0
}

find_shard_id() {
   for s in {1..3}; do
      # assume the harmony db in the ~ (home) directory
      if [ -d "$HOME/harmony_db_${s}" ]; then
         echo $s
         return
      fi
   done
   echo 0
}

download_db() {
   local status=0
   case "${CONFIG_KV[shard]}" in
      "all")
         sid=$(find_shard_id)
         _download_one_db 0 "$sid" || status=$?
         ;;
      0|1|2|3)
         _download_one_db "${CONFIG_KV[shard]}" || status=$? ;;
   esac

   case "${status}" in
      0) ;;
      *) echo "cannot download/find db: ${CONFIG_KV[shard]} / ${status}"
         return ${status} ;;
   esac
}

stop_harmony() {
   if pgrep harmony; then
      if systemctl list-unit-files harmony.service | grep -q enabled; then
         echo harmony node is running in systemd, stop it
         sudo systemctl stop harmony || return $?
      else
         if ! sudo pkill harmony; then
            echo can not kill harmony process
            return 1
         fi
      fi
   else
      echo harmony process is not running
   fi
   return 0
}

replace_db() {
   for s in {0..3}; do
      if [ -d "$HOME/harmony_db_${s}" ]; then
         backupdir=$(mktemp -u harmony_db_${s}.backup.XXXXXX)
         echo "backup harmony_db_${s} to $backupdir"
         mv -f "$HOME/harmony_db_${s}" "$HOME/$backupdir"
         mv harmony_db_${s} "$HOME" || return $?
         echo "replaced harmony_db_${s}"
      fi
   done
}

restart_harmony() {
   if systemctl list-unit-files harmony.service | grep -q enabled; then
      sudo systemctl restart harmony || return $?
      systemctl status harmony
   else
      echo "WARN: can only restart harmony service using systemd"
      echo "please manually restart harmony process"
   fi
}

case "$1" in
   "-h"|"-H"|"-?"|"--help")
      usage;;
esac

CONFIGFILE=${1:-default.json}

check_env || exit 2

NOW=$(date +%F.%T)
mkdir -p "$NOW"
pushd "$NOW" &> /dev/null

if ! download_config; then
   echo "Failed to download config file: ${CONFIGFILE}"
   exit 3
fi

parse_config

download_db || exit 4

stop_harmony || exit 5

replace_db || exit 6

restart_harmony || exit 7

popd &> /dev/null

rm -rf "$NOW"
