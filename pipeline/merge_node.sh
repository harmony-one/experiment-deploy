#!/bin/bash

# set -x

KEYDIR=${BLSKEYDIR:-~/unit/blskeys}
OUTPUTDIR=${BLSKEYDIR:-~/harmony/ansible/playbooks/roles/node/files}
HARMONYDB=~/harmony/nodedb/mainnet/harmony.go
INDEXES=()
KEYS=()
MAX_INDEX=359

node_ssh() {
   local ip=$1
   shift
   "${progdir}/node_ssh.sh" -p "${profile}" -n $ip "$@"
}

usage() {
   cat<<-EOU

Usage:
   merge a list of nodes into the last node.
   all the nodes have to be in the same shard.

* To merge running nodes, with IP addresses.
   merge_node.sh -p profile -I ip1 ip2 ... ipX

* To merge nodes are down already, with only key indexes.
   merge_node.sh -p profile -K key1 key2 ... IP

EOU
   exit
}

get_key() {
   # set -x
   for idx in $@; do
      key=$(grep -E "Index:.\" $idx \"" $HARMONYDB | grep -oE 'BlsPublicKey: "[a-z0-9]+"' | awk ' { print $2 } ' | tr -d \")
      KEYS+=($key)
   done
}

get_index() {
   local ip=$1
   local tmpfile=logs/merge/${ip}.json
   curl --location -s --request POST "http://$ip:9500/" \
               --header 'Content-Type: application/json' \
               --data-raw '{
                   "jsonrpc": "2.0",
                   "method": "hmy_getNodeMetadata",
                   "params": [
                   ],
                   "id": 1
               }' > $tmpfile

   blskeys[0]=$(cat $tmpfile | jq -r .result.blskey[0])
   blskeys[1]=$(cat $tmpfile | jq -r .result.blskey[1])
   blskeys[2]=$(cat $tmpfile | jq -r .result.blskey[2])

   index_list=
   for i in {0..2}; do
      if [ "${blskeys[${i}]}" != "null" ]; then
         index=$(grep -F ${blskeys[${i}]} $HARMONYDB | grep -oE 'Index:...[0-9]+' | grep -oE [0-9]+)
         INDEXES+=($index)
      fi
   done

   rm $tmpfile
}

find_host() {
   local ip=$1
   dns=$(host "$ip" | awk ' { print $NF } ' | awk -F\. ' { print $(NF-2) }' )
   case "$dns" in
   "amazonaws")
      echo "ec2-user@$ip" ;;
   "googleusercontent")
      echo "gce-user@$ip" ;;
   *)
      echo "WRONG" ;;
   esac
}

do_merge_ip() {
# get all indexes
   for ip in $*; do
      get_index $ip
   done

   shard=$(( ${INDEXES[0]} % 4 ))
   same_shard=true
# check if they are all in the same shard
   for idx in ${INDEXES[@]}; do
      s=$(( $idx % 4 ))
      if [ $shard != $s ]; then
         echo "#shard:$s of $i doesn't match $shard"
         same_shard=false
      else
         echo "#index: $idx in shard: $s"
         echo $idx >> logs/merge/$merged/multikey.txt
      fi
   done

   if [ "$same_shard" != "false" ]; then
      rm -rf logs/merge/$merged/*
      for ip in $*; do
         src=$(find_host $ip)
         if [ "$ip" != "$merged" ]; then
            echo scp -r $src:.hmy/blskeys/*.key logs/merge/$merged
         fi
      done
      dest=$(find_host $merged)
      echo scp -r logs/merge/$merged/*.key $dest:.hmy/blskeys
      echo scp logs/merge/$merged/multikey.txt $dest:
      echo ./restart_node.sh -p s3 -y -t 60 $merged
   fi
}

_copy_key() {
   set -x
   for k in "${KEYS[@]}"; do
      cat "$KEYDIR/${k}.key" | ./node_ssh.sh -p "${profile}" "$merged" "cat - > .hmy/blskeys/${k}.key"
      ./node_ssh.sh -p "${profile}" "$merged" "cp bls.pass .hmy/blskeys/${k}.pass"
      echo "copying ${k}.key to $merged"
   done
}

_delete_key() {
   set -x
   for k in "${KEYS[@]}"; do
      ./node_ssh.sh -p "${profile}" "$merged" "rm -f .hmy/blskeys/${k}.*"
      echo "deleting ${k}.key in $merged"
   done
}

do_merge_key() {
   indexes=$@

   get_index "$merged"

   for i in $indexes; do
      if [ "$i" != "$merged" ]; then
         INDEXES+=($i)
      fi
   done

   shard=$(( ${INDEXES[0]} % 4 ))
   same_shard=true
# check if they are all in the same shard
   for idx in "${INDEXES[@]}"; do
      s=$(( idx % 4 ))
      if [ $shard != $s ]; then
         echo "#shard:$s of $idx doesn't match $shard"
         same_shard=false
      else
         if [ "${idx}" -le "${MAX_INDEX}" ]; then
            echo "#index: $idx in shard: $s"
            echo "$idx" >> "logs/merge/$merged/multikey.txt"
            get_key "$idx"
         else
            echo "#index: skip $idx"
         fi
      fi
   done

   _copy_key

   ./restart_node.sh -p ${profile} -y -t 0 $merged
}

do_remove_key() {
   indexes=$@

   for idx in $indexes; do
      get_key $idx
   done

   _delete_key
}

do_copy_key() {
   indexes=$@

   for idx in $indexes; do
      get_key $idx
   done

   mkdir "$OUTPUTDIR/$merged"

   for k in "${KEYS[@]}"; do
      cp "$KEYDIR/${k}.key" "$OUTPUTDIR/$merged/${k}.key"
      cp "$KEYDIR/bls.pass" "$OUTPUTDIR/$merged/${k}.pass"
      echo "copying ${k} done."
   done
}

while getopts ":p:hIKRC" opt; do
   case "${opt}" in
      I) action=merge_ip ;;
      K) action=merge_key ;;
      R) action=remove_key ;;
      C) action=copy_key ;;
      p) profile=${OPTARG} ;;
      *) usage ;;
   esac
done
shift $(( OPTIND - 1 ))

merged=${!#}
mkdir -p "logs/merge/$merged"

case "$action" in
   "merge_ip") do_merge_ip "$@" ;;
   "merge_key") do_merge_key "$@" ;;
   "remove_key") do_remove_key "$@" ;;
   "copy_key") do_copy_key "$@" ;;
   *) usage ;;
esac
