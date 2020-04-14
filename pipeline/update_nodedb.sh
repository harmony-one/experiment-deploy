#!/usr/bin/env bash

# Assumptions:
# run from the pipeline directory
# experiment-deploy & nodedb repos are set up at the same level
# github credentials for nodedb exist for current user
# ssh watchdog is correctly configured

base=$(basename `realpath .`)
nodedb=$(realpath ../../nodedb)
logs=$(realpath logs)
watchdog="/home/jl/watchdog/nodedb"

help() {
  echo ""
  echo "Usage: ${0} -w [whoami] -t [target chain] -u -p -r"
  echo -e "\t-w WHOAMI (default = OS)"
  echo -e "\t-t Target directory in nodedb (default = ostn)"
  echo -e "\t-u Update the nodedb repo, if update fails, will try to copy files (default = false)"
  echo -e "\t-c Copy shard?.txt files from /logs to nodedb (default = false)"
  echo -e "\t-p Push the nodedb update (default = false)"
  echo -e "\t-r Restart Watchdog (default = false)"
  echo -e "\t-y Force yes (default = false)"
  exit
}

unset OPTARG whoami target update copy restart push yes
whoami="OS"
target="ostn"
update=false
copy=false
push=false
restart=false
yes=false
while getopts "t:w:ucpry" opt
do
  case "${opt}" in
    w ) whoami="${OPTARG}" ;;
    t ) target="${OPTARG}" ;;
    u ) update=true ;;
    c ) copy=true ;;
    p ) push=true ;;
    r ) restart=true ;;
    y ) yes=true ;;
    * ) help ;;
  esac
done

# Sanity check all the assumptions
if [[ "${base}" != "pipeline" ]]; then
  echo "[ERROR] Only run this script from experiment-deploy/pipeline"
  exit
fi

if [[ ! -d ${nodedb} ]]; then
  echo "[ERROR] Nodedb path does not exist"
  exit
fi

if [[ ! -d ${nodedb}/${target} ]]; then
  echo "[ERROR] Target directory must exist in Nodedb"
  exit
fi

# Only one of update or copy is true
if [[ "${copy}" == true ]] && [[ "${update}" == true ]]; then
  echo "[WARNING] Cannot use -c & -u at the same time"
  echo "[WARNING] Running using -u"
  copy=false
fi

# Update repo & reset
if [[ "${push}" == true ]]; then
  pushd ${nodedb}
  git reset --hard origin/master
  if git remote -v | grep -q nodedb; then
    git clean -xdf
    git pull
  else
    echo "[ERROR] Not in nodedb directory"
    popd
    exit
  fi
  popd
fi

if [[ "${update}" == true ]]; then
  echo "-- Updating nodedb for ${whoami} --"
  if [[ "${whoami}" == "s3" ]]; then
    # TODO: Mainnet nodedb update with nodedb.sh
    echo "[ERROR] Mainnet nodedb update not implemented"
  else
    # Run testnet update
    pushd ${nodedb}
    python3 -u testnet_nodedb.py --profile ${whoami} --network ${target}
    status=$?
    popd
  fi

  if [[ "${status}" == "50" ]]; then
    echo "[ERROR] Target directory must exist in nodedb repo"
    copy=true
  fi

  if [[ "${status}" == "100" ]]; then
    echo "[ERROR] Failures detected sorting IP lists"
    copy=true
  fi
else
  echo "-- Skipping nodedb update --"
fi

if [[ "${copy}" == true ]]; then
  echo "-- Copying files to nodedb for ${whoami} --"
  if [[ ! -d ${logs}/${whoami,,} ]]; then
    echo "[ERROR] Log path does not exist"
    exit
  fi
  # Assuming deploy log directory link is lowercase of WHOAMI
  cp ${logs}/${whoami,,}/shard?.txt ${nodedb}/${target}
  cp -r ${logs}/${whoami,,}/init ${nodedb}/${target}
fi

# Push to master on nodedb
if [[ "${push}" == true ]]; then
  pushd ${nodedb}
  git add ${target}/* > /dev/null 2&>1
  if [[ -z $(git status --porcelain) ]]; then
    echo "[INFO] No changes detected in nodedb, skipping commit & push"
  else
    if [[ "${yes}" == true ]]; then
      echo "-- Pushing nodedb update --"
    else
      git status
      read -rp "Push nodedb update? [Y/N]" reply
      echo
      if [[ "${reply}" != "Y" ]]; then
        exit
        popd
      fi
    fi
    git commit -m "[update_nodedb] Updating ip lists & init files for ${target}"
    git push -f
  fi
  popd
fi

# Restart Watchdog
if [[ "${restart}" == true ]]; then
  ./restart_watchdog.sh -a restart -s ${target} -u
fi
