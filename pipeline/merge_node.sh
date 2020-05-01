#!/bin/bash

# set -x

KEYDIR=${BLSKEYDIR:-~/tmp/blskey}
HARMONYDB=../tools/harmony.go
INDEXES=()
KEYS=()

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
   for idx in $@; do
      key=$(grep -E "Index:.\".$idx \"" $HARMONYDB | grep -oE 'BlsPublicKey: "[a-z0-9]+"' | awk ' { print $2 } ' | tr -d \")
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
   for k in "${KEYS[@]}"; do
      cat "$KEYDIR/${k}.key" | ./node_ssh.sh -p "${profile}" "$merged" "mkdir -p .hmy/blskeys; cat >> .hmy/blskeys/${k}.key2"
      echo "copying ${k}.key to $merged"
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
         echo "#index: $idx in shard: $s"
         echo "$idx" >> "logs/merge/$merged/multikey.txt"
         get_key "$idx"
      fi
   done

   _copy_key

   ./restart_node.sh -p ${profile} -y -t 60 $merged
}

while getopts ":p:hIK" opt; do
   case "${opt}" in
      I) action=merge_ip ;;
      K) action=merge_key ;;
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
   *) usage ;;
esac
