#!/usr/bin/env bash

export LD_LIBRARY_PATH=$(pwd)

PARALLEL=10
COUNT=10
SECOND=1
SLEEP=10
SHARDS=2
NET=cm


NUM_ACC=10
declare -A ADDR

ADDR["0"]=one17ccz029r57ulyxsqcsjduhgqsgvjpxltpt4lm3
ADDR["1"]=one1vzaz49jzumxx9p066stnt6p5c3jczkawjq098f
ADDR["2"]=one1n4fy844gv4rdlcquuueveavtu6zsqdf9et9yn7
ADDR["3"]=one13uyq3pvyee7jh84n87wn6ffwgl63d7lgnq7kvz
ADDR["4"]=one1dn430dcq0yd4x34x330pevve8pkla9ayp7v259
ADDR["5"]=one13nttw7ucw23fwnanj04tv26uj5xpvha4jazeum
ADDR["6"]=one17nhypqtfk88v6suutntjcy84lwrdyckdpz5sz0
ADDR["7"]=one1kuyxefj99lhc3yn3nmn6m48jhthzul45r6xpha
ADDR["8"]=one1mqcy64xeaeyrxp2gyq8a9tjreqzg9xyvwhqllr
ADDR["9"]=one1rq5a7j2g7aa355ywm2zzjm2hew7f43hg2ym89y
#ADDR["10"]=one1shzkj8tty2wu230wsjc7lp9xqkwhch2ea7sjhc
#ADDR["11"]=one1vjywuur8ckddmc4dsyx6qdgf590eu07ag9fg4a
#ADDR["12"]=one1wh4p0kuc7unxez2z8f82zfnhsg4ty6dupqyjt2
#ADDR["13"]=one1yc06ghr2p8xnl2380kpfayweguuhxdtupkhqzw


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
         from=${ADDR[$(expr $RANDOM % $NUM_ACC)]}
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
