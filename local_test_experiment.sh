# Kill nodes if any
./aws/kill_node.sh

go build -o bin/benchmark ../harmony-benchmark
go build -o bin/profiler ../harmony-benchmark/profiler/main.go
go build -o bin/txgen ../harmony-benchmark/client/txgen/main.go
go build -o bin/commander experiment/commander/main.go
go build -o bin/soldier experiment/soldier/main.go
cd bin

# Create a tmp folder for logs
t=`date +"%Y%m%d-%H%M%S"`
log_folder="tmp_log/log-$t"

mkdir -p $log_folder

# For each of the nodes, start soldier
config=distribution_config.txt
while IFS='' read -r line || [[ -n "$line" ]]; do
  IFS=' ' read ip port mode shardId <<< $line
	#echo $ip $port $mode
  ./soldier -ip $ip -port $port&
done < $config

./commander