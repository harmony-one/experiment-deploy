#!/usr/bin/env bash

set -x

THEPWD=$(pwd)

./create_deploy_soldiers.sh -c 25 -s 10 -t 1 -m 0 -u configs/userdata-soldier-http.sh

# ./launch-client-only.sh

./run_benchmark.sh kill

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

python3.7 ./terminate_instances.py

echo ============= TPS ==============
echo $TPS
