#!/usr/bin/env bash

set -x

THEPWD=$(pwd)
SKIPLEADER=true
PARALLEL=500

function usage
{
   ME=$(basename $0)
   cat<<EOT
Usage: $ME [OPTIONS] ACTIONS

This script automates the benchmark test.

[OPTIONS]
   -h          print this help message
   -n num      launch num soldiers (default: $NUM)
   -s          skip client launch (default: $SKIP)
   -S          skip power leader launch (default: $SKIPLEADER)
   -i file     raw ip file of client (default: $IPFILE)
   -d duration duration of the benchmark test (default: $DURATION)

[ACTIONS]
   launch      do launch only
   run         run benchmark
   log         download logs
   deinit      sync logs & terminate instances
   all         do everything (default)


[EXAMPLES]

EOT
   exit 0
}


while getopts "Shn:" option; do
   case $option in
      S) SKIPLEADER=true ;;
      h) usage ;;
      n) NUM=$OPTARG ;;
   esac
done

shift $(($OPTIND-1))

ACTION=$@

mkdir -p logs

SECONDS=0

./launch-client-only.sh &

if [ "$SKIPLEADER" == "false" ]; then
   ./launch-leaders-only.sh &
   LAUNCH_OPT='-l raw_ip-leaders.txt'
fi

wait

./create_deploy_soldiers.sh -c 2500 -s 50 -t 1 -m 0 -u configs/userdata-soldier-http.sh -i raw_ip-client.txt ${LAUNCH_OPT}

cat instance_ids_output-client.txt >> instance_ids_output.txt
cat instance_output-client.txt >> instance_output.txt

rm instance_ids_output-client.txt instance_output-client.txt raw_ip-client.txt &

if [ "$SKIPLEADER" == "false" ]; then
   cat instance_ids_output-leaders.txt >> instance_ids_output.txt
   cat instance_output-leaders.txt >> instance_output.txt
   rm instance_ids_output-leaders.txt instance_output-leaders.txt &
fi

#sleep 10
#./run_benchmark.sh ping

sleep 3

./run_benchmark.sh -n ${PARALLEL} config

sleep 3

./run_benchmark.sh -n ${PARALLEL} init

sleep 300

pushd logs
TS=$(ls -dlrt 2018* | tail -1 | awk -F ' ' ' { print $NF } ' )
popd

./dl-soldier-logs.sh -s $TS -g leader benchmark
pushd logs/$TS/leader/tmp_log/log-$TS
TPS=$( ${THEPWD}/cal_tps.sh )
popd

echo ============= TPS ==============
echo $TPS

sleep 3

./dl-soldier-logs.sh -s $TS -g client benchmark &
./dl-soldier-logs.sh -s $TS -p ${PARALLEL} -g validator benchmark &

# ./run_benchmark.sh kill &
# sleep 10

wait

aws s3 sync logs/$TS s3://harmony-benchmark/logs/$TS 2>&1 > /dev/null &
aws s3 sync logs/run s3://harmony-benchmark/logs/run 2>&1 > /dev/null &
./terminate_instances.py 2>&1 > /dev/null &

echo ============= TPS ==============
echo $TPS

wait

duration=$SECONDS

echo This Run Takes $(($duration / 60)) minutes and $(($duration % 60)) seconds
