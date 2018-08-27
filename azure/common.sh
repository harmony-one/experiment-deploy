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
# RG=$($JQ .resourceGroup $CONFIG | tr -d \")
REGIONS=( $($JQ ' .regions | .[] ' $CONFIG | tr "\n" " ") )

#set the default subscription id
az account set --subscription $SUBSCRIPTION

