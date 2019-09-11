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

test_read_profile
# test_find_available_node_index
