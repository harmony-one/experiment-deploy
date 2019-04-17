#!/bin/bash

source common.sh

read_profile ~/go/src/github.com/harmony-one/experiment-deploy/configs/benchmark-cello.json
# read_profile ~/go/src/github.com/harmony-one/experiment-deploy/configs/benchmark-tiny.json

function test_read_profile
{
   for k in ${!configs[@]}; do
      echo $k == ${configs[$k]}
   done
}

function test_find_available_node_index
{
   d=$(_find_available_node_index 1)
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
   d=$(_find_available_node_index 98)
   echo $d
   d=$(_find_available_node_index 99)
   echo $d
   d=$(_find_available_node_index 100)
   echo $d
}

test_find_available_node_index
