#!/bin/bash

# set -x

HARMONYDB=../tools/harmony.go
INDEXES=()

usage() {
   cat<<-EOU

Usage:
   merge a list of nodes into the last node.
   all the nodes have to be in the same shard.

   merge_node.sh ip1 ip2 ... ipX

EOU
   exit
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

if [[ $# -le 1 || "$1" = "-h" ]]; then
   usage
fi

merged=${!#}
mkdir -p logs/merge/$merged

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
