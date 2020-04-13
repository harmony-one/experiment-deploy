#!/usr/bin/env bash

# Assumptions:
# run from the pipeline directory
# experiment-deploy & nodedb repos are set up at the same level
# github credentials for nodedb exist for current user
# ssh watchdog is correctly configured

base=$(basename `realpath .`)
watchdog="/home/jl/watchdog/nodedb"

help() {
  echo ""
  echo "Usage: ${0} -a [action] -s [service] -u"
  echo -e "\t-a "
  echo -e "\t-s Target service to restart (default = ostn)"
  echo -e "\t-u Pull the nodedb repo on the Watchdog machine (default = false)"
  exit
}

unset OPTARG action service update
action="restart"
service="ostn"
update=false
while getopts "a:s:u" opt
do
  case "${opt}" in
    a ) action="$OPTARG" ;;
    s ) service="${OPTARG}" ;;
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
  lrtn ) ;;
  ostn ) ;;
  pstn ) ;;
  stn ) ;;
  all ) service="*" ;;
  * ) echo "[ERROR] Unknown service: ${service}"; exit ;;
esac
echo "Service: ${service}"

# Pull nodedb
if [[ "${update}" == true ]]; then
  echo "-- Pulling new nodedb --"
  ssh watchdog "sudo sh -c \"cd ${watchdog} && git reset --hard origin/master && git clean -xdf && git pull\"" > /dev/null 2&>1
else
  echo "-- Using existing nodedb --"
fi
ssh watchdog "sudo sh -c \"cd ${watchdog} && git show --oneline -s\""

# Watchdog
ssh watchdog "sudo systemctl ${action} harmony-watchdogd@${service}.service"
