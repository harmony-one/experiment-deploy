#!/usr/bin/env bash

# Assumptions:
# experiment-deploy & nodedb repos are set up in the path
# python3 installed & requests package is installed

base=`pwd`
nodedb=$(realpath ../../nodedb)

help() {
  echo ""
  echo "Usage; ${0} -p [profile] -t [target chain] -u"
  echo "\t-p WHOAMI (required)"
  echo "\t-t Target directory in nodedb (required)"
  echo "\t-u Update the nodedb repo"
  exit 1
}

unset OPTARG whoami target upload
whoami="OS"
target="ostn"
upload=false
while getopts "t:w:u" opt
do
  case "${opt}" in
    w ) whoami="${OPTARG}" ;;
    t ) target="${OPTARG}" ;;
    u ) upload=true ;;
    ? ) help ;;
  esac
done

# Check for required arguments
if [[ -z "${whoami}" ]] || [[ -z "${target}" ]]; then
  help
fi

# Update repo & reset
if [[ ${upload} == true ]]; then
  pushd ${nodedb}
  git reset --hard HEAD
  git checkout master
  git pull
  popd
fi

if [[ "${whoami}" == "s3" ]]; then
  # TODO: Mainnet nodedb update with nodedb.sh
  echo "Mainnet nodedb update not implemented"
else
  # Run testnet update
  pushd ${nodedb}
  python3 testnet_nodedb.py --profile ${whoami} --network ${target}
  popd
fi

# Push to master on nodedb
if [[ ${upload} == true ]]; then
  pushd ${nodedb}
  git add ${target}/*
  git commit -m "[db] Update ip lists for ${target}"
  # git push -f
  popd
fi
