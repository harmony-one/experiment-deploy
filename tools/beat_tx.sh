#!/usr/bin/env bash

# set -x

ACC=0xF6b57E6aaCb28abD5Bdf2ffe6f684be3DB8A6630
KEY=a2466bae151cd504199b9d8ec98056884082f4c4ebce79434497c5dcff5013b6
WALLET=./wallet
COUNT=100
NUM=100
SECOND=1
ACCOUNTS=accounts.txt
SHARDS=2
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

[ACTIONS]
   download       download the latest wallet from devnet
   reset          remove all local accounts
   beat           do beat transaction only
   new            create new accounts in $ACCOUNTS file
   request        request free tokens for each account in $ACCOUNTS file
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
      echo $new_acc >> $ACCOUNTS
      ((i++))
      echo new account $i: $new_acc
      sleep $SECOND
   done
}

function do_request_token
{
   while read acc; do
      ${WALLET} getFreeToken --address $acc
      sleep $SECOND
      echo get token $acc
   done < $ACCOUNTS
}

function do_beat
{
   local i=0
   while [ $i -lt $COUNT ]; do
      while read acc; do
         local s=0
         while [ $s -lt $SHARDS ]; do
            ${WALLET} transfer --from $acc --to $ACC --amount 0.001 --shardID $s
            sleep $SECOND
            ((s++))
         done
      done < $ACCOUNTS
      ((i++))
   done
}

function do_reset
{
   ${WALLET} removeAll
   rm -f $ACCOUNTS

   # import a new account
   ${WALLET} import --privateKey $KEY
}

function main
{
   do_download_wallet
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

while getopts "hp:vi:t:f:c:n:s:" option; do
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
   esac
done

shift $(($OPTIND-1))

ACTION=$*

if [ -z "$ACTION" ]; then
   ACTION=all
fi

case $ACTION in
   all) main ;;
   beat) do_beat ;;
   new) do_new_account ;;
   download) do_download_wallet ;;
   request) do_request_token ;;
   reset) do_reset ;;
esac

exit 0
