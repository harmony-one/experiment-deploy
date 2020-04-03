#!/usr/bin/env bash

# Assumptions:
# experiment-deploy & nodedb repos are set up in the path
# python3 installed & requests package is installed
# github credentials for nodedb exist for current user
# ssh watchdog is correctly configured

base=`pwd`
nodedb=$(realpath ../../nodedb)

help() {
  echo ""
  echo "Usage; ${0} -p [profile] -t [target chain] -u"
  echo -e "\t-p WHOAMI (default = OS)"
  echo -e "\t-t Target directory in nodedb (default = ostn)"
  echo -e "\t-u Update the nodedb repo"
  exit 1
}

unset OPTARG whoami target upload restart
whoami="OS"
target="ostn"
upload=false
restart=false
while getopts "t:w:ur" opt
do
  case "${opt}" in
    w ) whoami="${OPTARG}" ;;
    t ) target="${OPTARG}" ;;
    u ) upload=true ;;
    r ) restart=true ;;
    ? ) help ;;
  esac
done

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
  python3 -u testnet_nodedb.py --profile ${whoami} --network ${target}
  popd
fi

# Push to master on nodedb
if [[ ${upload} == true ]]; then
  pushd ${nodedb}
  git add ${target}/*
  git commit -m "[update_watchdog] Updating ip lists for ${target}"
  git push -f
  popd
  # Restart Watchdog
  if [[ ${restart} == true ]]; then
    ssh watchdog 'sudo sh -c "cd /home/jl/watchdog/nodedb && git stash && git pull -r"'
    ssh watchdog "sudo systemctl restart harmony-watchdogd@${target}.service && echo \"Restarting harmony-watchdogd@${chain}.service\""
  fi
fi
