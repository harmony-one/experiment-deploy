#!/usr/bin/env bash

export LD_LIBRARY_PATH=$(pwd)

PARALLEL=4
COUNT=200
SECOND=10
SLEEP=20
SHARDS=2
NET=beta


NUM_ACC=4
declare -A ADDR

ADDR["0"]=one1u2huc4ktjgf3qkpc2ph29l72jh2yh0d8hqjwy3
ADDR["1"]=one1hzxfgd7kvnwj86s8gfgjv8kg5d67kvjgpkegcu
ADDR["2"]=one1arv4kd462zk07ypuc0k5j78ky5cqhs85xts5n5
ADDR["3"]=one1m26snycwt4m9kzqrhmj2ul7s32spcj7l7kt8ft
#ADDR["4"]=one1yc06ghr2p8xnl2380kpfayweguuhxdtupkhqzw

function usage
{
   ME=$(basename $0)
   cat<<EOT
Usage: $ME [OPTIONS] ACTIONS

This script generates transaction and can be used as a test of token transfer. 

One Time Setup:
1. Generate several private keys into keystore if not exist; copy the 4 validator private keys from .hmy/keystore.beta 
   into .hmy/keystore. Here we assume the network is launched using betanet configuration. 
2. Fund the newly created addresses in all shards using the validator keys 
   After funded, remove the 4 validator keys from .hmy/keysotre and modify the ADDR dictionary using 
   the same indexes as shown by command "$ME b", after that, "$ME l" should give the same index
3. $ME st   (stress test)  


[OPTIONS]
   -h             print this help message
   -i second      interval second (default: $SECOND)
   -c count       run count number of times (default: $COUNT)
   -s shards      number of shards (default: $SHARDS)
   -P parallel    run wallet in parallel (default: $PARALLEL)

[ACTIONS]
   t              transfer
   l              list all accounts in $ACCOUNT_FILE file
   b              check the balances, or balance of given index account


[EXAMPLES]

   $ME  l  (list accounts with their indexes)
   $ME  b  (show balances) 
   $ME  b 7 (show balance of account index 7)
   $ME  t 13 6 0 1 5.5 (transfer from account 13 to account 6, from shard 0 to shard 1, with amount 5.5)

[NOTE]

EOT
   exit 0
}



function errexit
{
   echo "$@ . Exiting ..."
   exit -1
}

function list
{
    cap=$(( $NUM_ACC -1 ))
    for i in $(seq 0 1 $cap);do
        echo ADDR[$i]= ${ADDR[$i]}
    done
}

function balance 
{
    if [ -z "$1" ];then
       $WALLET balances 
    else
       $WALLET balances --address ${ADDR[$1]}
    fi
}

function transfer
{
    echo from [${ADDR[$1]}] to [${ADDR[$2]}], from shard [$3] to shard [$4] with amount: [$5]
    $WALLET transfer --from ${ADDR[$1]} --to ${ADDR[$2]} --shardID $3 --toShardID $4 --amount $5 --pass file:empty.txt
}

function sum_balance
{
    local bal
    if [ -z "$1" ];then
       bal=$($WALLET balances | ag -o  "[+-]?([0-9]*[.])?[0-9]+, nonce" |awk '{ SUM += $1} END { print SUM }')
    else
       bal=$($WALLET balances --address ${ADDR[$1]} | ag -o  "[+-]?([0-9]*[.])?[0-9]+, nonce" |awk '{ SUM += $1} END { print SUM }')
    fi
    echo $bal
}

function sum_nonce
{
    local nonce
    if [ -z "$1" ];then
        nonce=$($WALLET balances |  ag -o  "nonce: [0-9]+" |awk '{ SUM += $2} END { print SUM }') 
    else
        nonce=$($WALLET balances --address ${ADDR[$1]} |  ag -o  "nonce: [0-9]+" |awk '{ SUM += $2} END { print SUM }')
    fi
    echo $nonce
}

function stress_test
{
   local bal=`sum_balance`
   local nonce0=`sum_nonce`
   local i=0
   while [ $i -lt $COUNT ]; do
      local p=0
      while [ $p -lt $PARALLEL ]; do
         #from=${ADDR[$(expr $RANDOM % $NUM_ACC)]}
         from=${ADDR[$p]}
         to=${ADDR[$(expr $RANDOM % $NUM_ACC)]}
         fid=$(expr $RANDOM % $SHARDS)
         tid=$(expr $RANDOM % $SHARDS)
         v=0.00$RANDOM

         echo from [$from] to [$to], from shard [$fid] to shard [$tid] with amount: [$v]
         $WALLET transfer --from $from --to $to --amount $v --shardID $fid --toShardID $tid --pass file:empty.txt &
         sleep 1
         ((p++))
      done
      wait
      sleep $SECOND
      # wallet process will create dht folder; remove it after test
      rm -r .dht-*
      ((i++))
   done

   echo waiting $SLEEP seconds for transaction finish ........
   sleep $SLEEP
   local bal1=`sum_balance`
   if [ "$bal" != "$bal1" ];then
       echo balance not equal, before $bal, after $bal1, fail balance test
   else
       echo balance equal $bal, pass balance test!!!
   fi

   local nonce1=$(( $COUNT*$PARALLEL ))
   local nonce2=`sum_nonce`
   local nonce3=$(( $nonce0 + $nonce1 ))
   if [ "$nonce2" != "$nonce3" ];then
       echo nonce not match, before $nonce0, added $nonce1, after $nonce2, fail nonce test
   else
       echo nonce matches $nonce2, pass balance test!!!
   fi
}


while getopts ":h:i:c:s:P:n:" option; do
   case $option in
      h) usage ;;
      i) SECOND=$OPTARG ;;
      c) COUNT=$OPTARG ;;
      s) SHARDS=$OPTARG ;;
      n) NET=$OPTARG ;;
      P) PARALLEL=$OPTARG ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$1
shift

if [ -z "$ACTION" ]; then
   usage
fi

WALLET="./wallet -p $NET"

case $ACTION in
   l) list ;;
   b) balance $* ;;
   t) transfer $@ ;;
   sb) sum_balance $@ ;;
   sn) sum_nonce $@ ;;
   st) stress_test ;;
   *) errexit "unknown action: '$ACTION'" ;;
esac

exit 0
