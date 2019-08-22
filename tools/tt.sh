#!/usr/bin/env bash

# set -x

BUCKET=pub.harmony.one
OS=$(uname -s)
REL=r3

case "$OS" in
    Darwin)
        FOLDER=release/darwin-x86_64/${REL}/
        BIN=( wallet libbls384_256.dylib libcrypto.1.0.0.dylib libgmp.10.dylib libgmpxx.4.dylib libmcl.dylib )
        export DYLD_FALLBACK_LIBRARY_PATH=$(pwd)
        ;;
    Linux)
        FOLDER=release/linux-x86_64/${REL}/
        BIN=( wallet libbls384_256.so libcrypto.so.10 libgmp.so.10 libgmpxx.so.4 libmcl.so )
        export LD_LIBRARY_PATH=$(pwd)
        ;;
    *)
        echo "${OS} not supported."
        exit 2
        ;;
esac

######### VARIABLES #########
VERBOSE=
THEPWD=$(pwd)
JQ='jq -r -M'
SKIP_DOWNLOAD=true
PARALLEL=10
NETWORK=beta
NEWACC=( one13nttw7ucw23fwnanj04tv26uj5xpvha4jazeum one17nhypqtfk88v6suutntjcy84lwrdyckdpz5sz0 one1kuyxefj99lhc3yn3nmn6m48jhthzul45r6xpha one1mqcy64xeaeyrxp2gyq8a9tjreqzg9xyvwhqllr one1rq5a7j2g7aa355ywm2zzjm2hew7f43hg2ym89y )
BETA=( one1shzkj8tty2wu230wsjc7lp9xqkwhch2ea7sjhc one1vjywuur8ckddmc4dsyx6qdgf590eu07ag9fg4a one1wh4p0kuc7unxez2z8f82zfnhsg4ty6dupqyjt2 one1yc06ghr2p8xnl2380kpfayweguuhxdtupkhqzw )
COUNT=10
NUM=5
SECOND=1
ACCOUNT_FILE=accounts.txt
SHARDS=2
CROSS=false

function usage
{
   ME=$(basename $0)
   cat<<EOT
Usage: $ME [OPTIONS] ACTIONS

This script generates transaction and can be used as a test of token transfer.

[OPTIONS]
   -h             print this help message
   -v             verbose output
   -i second      interval second (default: $SECOND)
   -t address     the To address of the transaction
   -f address     the From address of the transaction
   -c count       run count number of times (default: $COUNT)
   -n number      new number of account (default: $NUM)
   -s shards      number of shards (default: $SHARDS)
   -k             skip download (default: $SKIP_DOWNLOAD)
   -P parallel    run wallet in parallel (default: $PARALLEL)
   -N network     specify the network type (default: $NETWORK)
   -C             enable cross shard tx (default: $CROSS)

[ACTIONS]
   download       download the latest wallet from release
   reset          remove all local accounts
   beat           do beat transaction only
   new            create new accounts in $ACCOUNT_FILE file
   list           list all accounts in $ACCOUNT_FILE file
   fund           fund a list of accounts ${NEWACC[@]}
   balance        check the balances


[EXAMPLES]

   $ME -i 3
   $ME -i 1

[NOTE]

EOT
   exit 0
}

function verbose
{
   [ $VERBOSE ] && echo $@
}

function errexit
{
   echo "$@ . Exiting ..."
   exit -1
}

function do_download_wallet
{
# clean up old files
    for bin in "${BIN[@]}"; do
        rm -f ${bin}
    done

# download all the binaries
    for bin in "${BIN[@]}"; do
        curl http://${BUCKET}.s3.amazonaws.com/${FOLDER}${bin} -o ${bin}
    done

    mkdir -p .hmy/keystore
    chmod +x wallet
}

function do_new_account
{
   local i=0
   rm -f $ACCOUNT_FILE
   while [ $i -lt $NUM ]; do
      new_acc=$(${WALLET} new --nopass | grep -oE one1[0-9a-z]*$)
      echo $new_acc >> $ACCOUNT_FILE
      ((i++))
      echo new account $i: $new_acc
   done
}

function _do_get_accounts
{
   readarray -t ACCOUNTS < $ACCOUNT_FILE

   NUM_ACCOUNTS=${#ACCOUNTS[@]}
   NUM_NEWACC=${#NEWACC[@]}
}

function do_beat
{
   _do_get_accounts

   mv .hmy/keystore .hmy/keystore.bak
   mv .hmy/keystore.newacc .hmy/keystore

   local i=0
   while [ $i -lt $COUNT ]; do
      local p=0
      while [ $p -lt $PARALLEL ]; do
         local s=0
         from=${NEWACC[$(expr $RANDOM % $NUM_NEWACC)]}
         to=${ACCOUNTS[$(expr $RANDOM % $NUM_ACCOUNTS)]}
         while [ $s -lt $SHARDS ]; do
            v=0.000$RANDOM
            echo transfering from $from to $to on shard $s - amount: $v
            if [ "$CROSS" == "true" ]; then
               tos=$(expr $SHARDS - $s - 1)
               echo ${WALLET} transfer --from $from --to $to --amount $v --shardID $s --toShardID $tos --inputData $(shuf -n5 /usr/share/dict/words | tr '\n' ' ' | base64) --pass file:empty.txt
            else
               ${WALLET} transfer --from $from --to $to --amount $v --shardID $s --inputData $(shuf -n5 /usr/share/dict/words | tr '\n' ' ' | base64) --pass file:empty.txt &
            fi
            sleep 1
            ((s++))
         done
         ((p++))
      done
      wait
      sleep $SECOND
      ((i++))
   done

   mv .hmy/keystore .hmy/keystore.newacc
   mv .hmy/keystore.bak .hmy/keystore
}

function do_fund
{
   mv .hmy/keystore .hmy/keystore.new
   mv .hmy/keystore.beta .hmy/keystore
   for acc in ${BETA[@]}; do
      for newacc in ${NEWACC[@]}; do
         local s=0
         while [ $s -lt $SHARDS ]; do
            ${WALLET} transfer --from $acc --to $newacc --amount 100 --inputData $(shuf -n5 /usr/share/dict/words | tr '\n' ' ' | base64) --shardID $s --pass file:empty.txt &
            sleep 1
            ((s++))
         done
      wait
      done
   done
   mv .hmy/keystore .hmy/keystore.beta
   mv .hmy/keystore.new .hmy/keystore
}

function do_balance
{
   local att=$1
   case $att in
      beta)
         mv .hmy/keystore .hmy/keystore.bak
         mv .hmy/keystore.beta .hmy/keystore
         ;;
      newacc)
         mv .hmy/keystore .hmy/keystore.bak
         mv .hmy/keystore.newacc .hmy/keystore
         ;;
   esac

   ${WALLET} balances

   case $att in
      beta)
         mv .hmy/keystore .hmy/keystore.beta
         mv .hmy/keystore.bak .hmy/keystore
         ;;
      newacc)
         mv .hmy/keystore .hmy/keystore.newacc
         mv .hmy/keystore.bak .hmy/keystore
         ;;
   esac

}

function do_reset
{
   ${WALLET} removeAll
   rm -f $ACCOUNT_FILE
}

function do_list
{
   ${WALLET} list | grep -oE one1[0-9a-z]*$ | tee $ACCOUNT_FILE
}

while getopts "hp:vi:t:f:c:n:s:kP:N:C" option; do
   case $option in
      h) usage ;;
      p) PROFILE=$OPTARG ;;
      v) VERBOSE=1 ;;
      i) SECOND=$OPTARG ;;
      t) TO=$OPTARG ;;
      f) FROM=$OPTARG ;;
      c) COUNT=$OPTARG ;;
      n) NUM=$OPTARG ;;
      s) SHARDS=$OPTARG ;;
      k) SKIP_DOWNLOAD=true ;;
      P) PARALLEL=$OPTARG ;;
      N) NETWORK=$OPTARG ;;
      C) CROSS=true ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$1
shift

if [ -z "$ACTION" ]; then
   usage
fi

WALLET="./wallet -p $NETWORK"

case $NETWORK in
   default) # mainnet
   ;;
   pangaea) # pangaea network
      ;;
   beta) # beta net
   ;;
   local) # local net
   ;;
   *)
      errexit "unknown network type: $NETWORK"
      ;;
esac

case $ACTION in
   beat) do_beat ;;
   new) do_new_account ;;
   download) do_download_wallet ;;
   reset) do_reset ;;
   fund) do_fund ;;
   list) do_list ;;
   balance) do_balance $* ;;
   *) errexit "unknown action: '$ACTION'" ;;
esac

exit 0
