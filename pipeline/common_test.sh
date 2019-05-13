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

function test_is_archival
{
   num=( 3 11 15 22 29 30 33 40 45 46 50 60 66 67 75 77 88 89 90 121 )

   for n in ${num[@]}; do
#      _is_archival $n
      if $(_is_archival $n);  then
         echo $n is archival node
      else
         echo $n is not archival node
      fi
   done
}

# test_find_available_node_index
test_is_archival
