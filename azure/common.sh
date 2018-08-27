#!/bin/bash

# init all the environment variables and configurations

#login to azure using your credentials
az account show 1> /dev/null

if [ $? != 0 ];
then
    az login
fi

CONFIG=configs/azure-env.json
# set mono, raw output
JQ="jq -M -r"

SUBSCRIPTION=$($JQ .subscriptionId $CONFIG)
REGIONS=( $($JQ ' .regions | .[] ' $CONFIG) )

#set the default subscription id
az account set --subscription $SUBSCRIPTION

#check the region is valid or not
function is_valid_region
{
   local match=1
   local r=$1

   if [ -z "$r" ]; then
      return $match
   fi

   for region in "${REGIONS[@]}"; do
      # run on specificed region
      if [ "$region" != "$r" ]; then
         continue
      else
         match=0
         break
      fi
   done

   return $match
}
