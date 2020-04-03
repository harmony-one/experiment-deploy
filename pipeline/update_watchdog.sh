#!/usr/bin/env bash

# Assumptions:
# experiment-deploy & nodedb repos are set up in the path
# python3 installed & requests package is installed
# github credentials for nodedb exist for current user
# ssh watchdog is correctly configured

nodedb=$(realpath ../../nodedb)
watchdog="/home/jl/watchdog/nodedb"

help() {
  echo ""
  echo "Usage; ${0} -p [profile] -t [target chain] -u"
  echo -e "\t-p WHOAMI (default = OS)"
  echo -e "\t-t Target directory in nodedb (default = ostn)"
  echo -e "\t-u Update the nodedb repo (default = false)"
  echo -e "\t-p Push the nodedb update (default = false)"
  echo -e "\t-r Restart Watchdog (default = false)"
  echo -e "\t-y Force yes (default = false)"
  exit
}

unset OPTARG whoami target update restart push yes
whoami="OS"
target="ostn"
update=false
push=false
restart=false
yes=false
while getopts "t:w:upry" opt
do
  case "${opt}" in
    w ) whoami="${OPTARG}" ;;
    t ) target="${OPTARG}" ;;
    u ) update=true;;
    p ) push=true ;;
    r ) restart=true ;;
    y ) yes=true ;;
    ? ) help ;;
  esac
done

# Update repo & reset
if [[ "${push}" == true ]]; then
  pushd ${nodedb}
  git reset --hard origin/master
  git clean -xdf
  git pull
  popd
fi

if [[ "${update}" == true ]]; then
  echo "-- Updating nodedb for ${whoami} --"
  if [[ "${whoami}" == "s3" ]]; then
    # TODO: Mainnet nodedb update with nodedb.sh
    echo "Mainnet nodedb update not implemented"
  else
    # Run testnet update
    pushd ${nodedb}
    python3 -u testnet_nodedb.py --profile ${whoami} --network ${target}
    status=$?
    popd
  fi

  if [[ "${status}" == "100" ]]; then
    echo "!! Failures detected sorting IP lists. Exiting... !!"
    exit 1
  fi
else
  echo "-- Skipping nodedb update --"
fi

# Push to master on nodedb
if [[ "${push}" == true ]]; then
  if [[ "${yes}" == true ]]; then
    echo "-- Pushing nodedb update --"
  else
    read -rp "Push nodedb update? [Y/N]" reply
    echo
    if [[ "${reply}" != "Y" ]]; then
      exit
    fi
  fi
  pushd ${nodedb}
  git add ${target}/*
  git commit -m "[update_watchdog] Updating ip lists for ${target}"
  git push -f
  popd
fi

# Restart Watchdog
if [[ "${restart}" == true ]]; then
  echo "-- Restarting Watchdog for ${target} --"
  ssh watchdog "sudo sh -c \"cd ${watchdog} && git reset --hard origin/master && git clean -xdf && git pull\""
  ssh watchdog "sudo systemctl restart harmony-watchdogd@${target}.service && echo \"Restarting harmony-watchdogd@${chain}.service\""
fi
