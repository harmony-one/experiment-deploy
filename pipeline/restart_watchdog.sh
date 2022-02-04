#!/usr/bin/env bash

# Assumptions:
# run from the pipeline directory
# experiment-deploy & nodedb repos are set up at the same level
# github credentials for nodedb exist for current user
# ssh watchdog is correctly configured

base=$(basename `realpath .`)
watchdog="/usr/local/watchdog"
nodedb="/usr/local/watchdog/nodedb"

help() {
  echo ""
  echo "Usage: ${0} -a [action] -s [service] -u"
  echo -e "\t-a "
  echo -e "\t-s Target service to restart (default = ostn)"
  echo -e "\t-b Build latest Watchdog binaries"
  echo -e "\t-u Pull the nodedb repo on the Watchdog machine (default = false)"
  exit
}

unset OPTARG action service build update
action="restart"
service="ostn"
build=false
update=false
while getopts "a:s:bu" opt
do
  case "${opt}" in
    a ) action="$OPTARG" ;;
    s ) service="${OPTARG}" ;;
    b ) build=true ;;
    u ) update=true ;;
    * ) help ;;
  esac
done

# Check valid action
case ${action} in
  start ) ;;
  stop ) ;;
  restart ) ;;
  * ) echo "[ERROR] Unknown action: ${action}"; exit ;;
esac
echo "Action: ${action}"

# Check valid service
case ${service} in
  mainnet ) ;;
  testnet ) ;;
  devnet ) ;;
  lrtn ) ;;
  ostn ) ;;
  pstn ) ;;
  stn ) ;;
  all ) service="*" ;;
  * ) echo "[ERROR] Unknown service: ${service}"; exit ;;
esac
echo "Service: ${service}"

if [[ "${build}" == true ]]; then
  echo "-- Building new Watchdog binary --"
  sudo sh -c "cd ${watchdog}/master && git reset --hard origin/master && git clean -xdf && git pull && PATH=\$PATH:/usr/local/go/bin make"
fi

# Pull nodedb
if [[ "${update}" == true ]]; then
  echo "-- Pulling new nodedb --"
  sudo sh -c "cd ${nodedb} && git reset --hard origin/master && git clean -xdf && git pull" > /dev/null
else
  echo "-- Using existing nodedb --"
fi

sudo sh -c "cd ${nodedb} && git show --oneline -s"

# Watchdog
sudo systemctl ${action} harmony-watchdogd@${service}.service
