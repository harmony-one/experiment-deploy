#!/bin/bash

# init all the environment variables and configurations

#login to azure using your credentials
az account show 1> /dev/null

if [ $? != 0 ];
then
    az login
fi

CONFIG=configs/azure-env.json
JQ="jq -M"

SUBSCRIPTION=$($JQ .subscriptionId $CONFIG | tr -d \")
# RG=$($JQ .resourceGroup $CONFIG | tr -d \")
REGIONS=( $($JQ ' .regions | .[] ' $CONFIG | tr "\n" " " | tr -d \") )
