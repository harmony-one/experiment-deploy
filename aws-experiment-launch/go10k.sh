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
   -n num      launch num soldiers
   -s          skip client launch
   -i file     raw ip file of client (default: $IPFILE)
   -d duration duration of the benchmark test (default: $DURATION)

[ACTIONS]


[EXAMPLES]

EOT
   exit 0
}

./launch-client-only.sh

./create_deploy_soldiers.sh -c 1250 -s 10 -t 1 -m 0 -u configs/userdata-soldier-http.sh -i raw_ip-client.txt

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

./dl-soldier-logs.sh -s $TS -g all benchmark

./run_benchmark.sh kill

sleep 10

pushd logs/$TS/leader/tmp_log/log-$TS
TPS=$( ${THEPWD}/cal_tps.sh )
popd

aws s3 sync logs s3://harmony-benchmark/logs &

./terminate_instances.py

wait

echo ============= TPS ==============
echo $TPS
