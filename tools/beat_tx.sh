#!/usr/bin/env bash

# set -x

declare -A ACCOUNTS

ACC=0xF6b57E6aaCb28abD5Bdf2ffe6f684be3DB8A6630
KEY=a2466bae151cd504199b9d8ec98056884082f4c4ebce79434497c5dcff5013b6
# LD_LIBRARY_PATH=$(pwd)
BINARY=./wallet
COUNT=10000
NUM=100
SECOND=1
ACCOUNT_FILE=accounts.txt
SHARDS=1
WALLET_URL=https://s3-us-west-1.amazonaws.com/pub.harmony.one

function usage
{
   ME=$(basename $0)
   cat<<EOT
Usage: $ME [OPTIONS] ACTIONS

This script generate beat transaction based on profile.

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
   -w binary      the name of the wallet binary (default: $BINARY)

[ACTIONS]
   download       download the latest wallet from devnet
   reset          remove all local accounts
   beat           do beat transaction only
   new            create new accounts in $ACCOUNT_FILE file
   request        request free tokens for each account in $ACCOUNT_FILE file
   all            do reset, new account, request token, and beat (default)


[EXAMPLES]

   $ME -i 3
   $ME -i 1

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
   case $(uname -s) in
      Linux)
         dl_folder=wallet ;;
      Darwin)
         dl_folder=wallet.osx ;;
   esac
   curl -O ${WALLET_URL}/$dl_folder/wallet

   chmod +x wallet
}

function do_new_account
{
   local i=0
   while [ $i -lt $NUM ]; do
      new_acc=$(${WALLET} new | grep -o {0x.*} | tr -d {})
      echo $new_acc >> $ACCOUNT_FILE
      ((i++))
      echo new account $i: $new_acc
   done
}

function do_request_token
{
   while read acc; do
      ${WALLET} getFreeToken --address $acc
      sleep $SECOND
      echo get token $acc
   done < $ACCOUNT_FILE
}

function _do_get_accounts
{
   local i=0
   while read acc; do
      ACCOUNTS[$i]=$acc
      ((i++))
   done < $ACCOUNT_FILE

   NUM_ACCOUNTS=$i
}

function do_beat
{
   _do_get_accounts

   local i=0
   while [ $i -lt $COUNT ]; do
      from=${ACCOUNTS[$(expr $RANDOM % $NUM_ACCOUNTS)]}
      to=${ACCOUNTS[$(expr $RANDOM % $NUM_ACCOUNTS)]}

      local s=0
      while [ $s -lt $SHARDS ]; do
         echo transfering from $from to $to on shard $s
         ${WALLET} transfer --from $from --to $to --amount 0.001 --shardID $s
         sleep $SECOND
         ((s++))
      done
      ((i++))
   done
}

function do_reset
{
   ${WALLET} removeAll
   rm -f $ACCOUNT_FILE

   # import a new account
   ${WALLET} import --privateKey $KEY
}

function main
{
   if [ "$SKIP_DOWNLOAD" == "false" ]; then
      do_download_wallet
   fi
   sleep 1
   do_reset
   sleep 1
   do_new_account
   sleep 3
   do_request_token
   sleep 3
   do_beat
}

######### VARIABLES #########
VERBOSE=
THEPWD=$(pwd)
JQ='jq -r -M'
SKIP_DOWNLOAD=false

while getopts "hp:vi:t:f:c:n:s:kw:" option; do
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
      w) BINARY=$OPTARG ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$*

if [ -z "$ACTION" ]; then
   ACTION=all
fi

# On node instance, we need to setup LD_LIBRARY_PATH
WALLET=$BINARY

case $ACTION in
   all) main ;;
   beat) do_beat ;;
   new) do_new_account ;;
   download) do_download_wallet ;;
   request) do_request_token ;;
   reset) do_reset ;;
esac

exit 0
