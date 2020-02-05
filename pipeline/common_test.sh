#!/bin/bash

source common.sh

PROFILE=${1:-pr100}

read_profile ~/go/src/github.com/harmony-one/experiment-deploy/configs/benchmark-$PROFILE.json

function test_read_profile
{
   for k in ${!configs[@]}; do
      echo $k == ${configs[$k]}
   done

}

function test_read_blskey
{
   for i in ${blskey[@]}; do
      echo $i
   done
}

function test_read_genesis_file
{
   for i in ${genesis[@]}; do
      echo $i
   done
}

function test_find_available_node_index
{
   d=$(_find_available_node_index 1)
   echo $d
   d=$(_find_available_node_index 2)
   echo $d
   d=$(_find_available_node_index 45)
   echo $d
   d=$(_find_available_node_index 46)
   echo $d
   d=$(_find_available_node_index 49)
   echo $d
   d=$(_find_available_node_index 50)
   echo $d
   d=$(_find_available_node_index 51)
   echo $d
   d=$(_find_available_node_index 92)
   echo $d
   d=$(_find_available_node_index 98)
   echo $d
   d=$(_find_available_node_index 99)
   echo $d
   d=$(_find_available_node_index 190)
   echo $d
}

# test_read_blskey

# test_read_profile
# test_find_available_node_index

function test_gen_multi_key
{
   keys=$(gen_multi_key 2 10 2 0 0)
   if [ "$keys" != "0 10" ]; then
      echo failed, got "'$keys'", expect "'0 10'"
   fi
   keys=$(gen_multi_key 2 10 2 0 1)
   if [ "$keys" != "2 12" ]; then
      echo failed, got "'$keys'", expect "'2 12'"
   fi
   keys=$(gen_multi_key 2 10 3 0 3)
   if [ "$keys" != "18" ]; then
      echo failed, got "'$keys'", expect "'18'"
   fi
   keys=$(gen_multi_key 2 10 3 1 3)
   if [ "$keys" != "19" ]; then
      echo failed, got "'$keys'", expect "'19'"
   fi
   keys=$(gen_multi_key 3 11 3 1 3)
   if [ "$keys" != "28 31" ]; then
      echo failed, got "'$keys'", expect "'28 31'"
   fi
}

test_gen_multi_key
