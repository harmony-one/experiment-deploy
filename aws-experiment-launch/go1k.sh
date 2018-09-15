#!/usr/bin/env bash

set -x

THEPWD=$(pwd)

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

mkdir -p logs

./launch-client-only.sh

./create_deploy_soldiers.sh -c 125 -s 10 -t 1 -m 0 -u configs/userdata-soldier-http.sh -i raw_ip-client.txt

cat instance_ids_output-client.txt >> instance_ids_output.txt
cat instance_output-client.txt >> instance_output.txt

sleep 10

./run_benchmark.sh ping

sleep 10

./run_benchmark.sh config

sleep 10

./run_benchmark.sh init

sleep 300

pushd logs
TS=$(ls -dlrt 2018* | tail -1 | awk -F ' ' ' { print $NF } ' )
popd

./dl-soldier-logs.sh -s $TS -g leader benchmark
./dl-soldier-logs.sh -s $TS -g client benchmark

./run_benchmark.sh kill

sleep 10

pushd logs/$TS/leader/tmp_log/log-$TS
TPS=$( ${THEPWD}/cal_tps.sh )
popd

aws s3 sync ${CACHE}logs/$TS s3://harmony-benchmark/logs/$TS &
aws s3 sync logs/run s3://harmony-benchmark/logs/run &

./terminate_instances.py

wait

echo ============= TPS ==============
echo $TPS
