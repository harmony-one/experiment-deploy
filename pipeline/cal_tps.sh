#!/usr/bin/env bash

LEADERS=$1
VALIDATORS=$2

if [ -z "$LEADERS" ]; then
   FILES=( $(ls leader-*.log) )
else
   FILES=( $(cat $LEADERS) )
fi

if [ -n "$VALIDATORS" ]; then
   NUM_VALIDATORS=$(wc -l $VALIDATORS | awk ' { print $1 } ')
fi

NUM_SHARDS=${#FILES[@]}
SUM=0
NUM_CONSENSUS=0

declare -A TPS

for f in "${FILES[@]}"; do
   leader=$( echo $(basename $f) | cut -f 2 -d\- )
   num_consensus=$(grep TPS $f | wc -l)
   if [ $num_consensus -gt 0 ]; then
      avg_tps=$(grep TPS $f | cut -f 2 -d: | cut -f 1 -d , | awk '{s+=$1} END {print s/NR}')
      printf -v avg_tps_int %.0f $avg_tps
   else
      avg_tps=0
   fi
   TPS[$leader]="$num_consensus, $avg_tps"
   NUM_CONSENSUS=$(expr $NUM_CONSENSUS + $num_consensus )
   SUM=$( expr $SUM + $avg_tps_int )
done

echo $NUM_SHARDS shards, $NUM_CONSENSUS consensus, $SUM total TPS, $NUM_VALIDATORS nodes
for t in "${!TPS[@]}"; do
   echo $t, ${TPS[$t]}
done
