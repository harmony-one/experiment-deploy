# Introduction
This document describe the key in benchmark-xxx.json configuration files.

## description
* string
* purpose and summary of this benchmark configuration

## client
This section is the  configuration of client nodes in AWS (legacy mode).
This section is no currently used in peer discovery mode.

### client.num_vm
* integer
* number of client nodes

### client.type
* string
* type of the EC2 instances

### client.regions
* string
* list of AWS regions to launch client nodes. The total number of client nodes is (client.num_vm * client.regions).

## leader
This section is the configuration of leader nodes in AWS.

Note: We use a separate configuration section for leader as we may usually use a more powerful instance type for leaders.
Also, leaders have to be running on on-demand instance to avoid sudden shutdown of the instances.
We will keep this kind of configuration until we have a reliable way of switching leaders.

### leader.num_vm
* integer
* number of leader nodes

### leader.type
* string
* type of the EC2 instances

### leader.regions
* string
* list of AWS regions to launch leader nodes. The total number of leader nodes is (leader.num_vm * leader.regions)

## beacon
This section is the configuration of beacon chain/nodes.

### beacon.server
* string
* The IP/name of the beacon node service.

### beacon.port
* integer
* The port number of the beacon node service.

### beacon.user
* string
* The user name to access the beacon node. This is field is not used as beacon node is open to public and no authentication is supported.

### beacon.key
* string
* The name of the private key used to access beacon server.

## azure
This section is the configuration of Azure.

### azure.num_vm
* integer
* The number of VMs launched in each region.

### azure.regions
* list
* The list of regions to launch VMs in Azure.

## benchmark
THis section is about some basic configuration of the launch of the blockchain network.

### benchmark.shards
* integer
* The number of shards in the network. It is hardcoded here now.

### benchmark.duration
* integer
* The duration of the txgen will run.

### benchmark.dashboard
* true/false
* The variable to control if we are using dashboard for this configuration network launch. We should set it to false other than the official devnet to avoid confusion of the dashboard.

### benchmark.crosstx
* integer
* The percentage of the cross shard transaction. This is a parameter used in txgen.

### benchmark.attacked_mode
* integer
* The parameter to control what kind of attack mode we are simulating in the network. 0 means no attack.

### benchmark.minpeer
* integer
* The parameter to control the minimal number of peers for leader to start the consensus.

## logs
This section controls which logs we shall download from running nodes.

### logs.leader
* true/false
* This variable controls if we download the leader.log file or not after the benchmark test.

### logs.client
* true/false
* This variable controls if we download the client.log (txgen) file or not after the benchmark test.

### logs.validator
* true/false
* This variable controls if we download the validator.log file or not after the benchmark test.

### logs.soldier
* true/false
* This variable controls if we download all the soldier.log file or not after the benchmark test. The soldier log can help triage the benchmark binary runtime problem.

## dashboard
This section is the configuration information of the dashboard server.

### dashboard.server
* string
* The IP/name of the server running dashboard service.

### dashboard.port
* integer
* The port number of the dashboard service.

### dashboard.reset
* true/false
* This variable controls if we want to reset the dashboard server before running the benchnmark test.

## explorer
This section is the configuration information of the blockchain explorer server.

### explorer.server
* string
* The IP/name of the server running blockchain explorer service.

### explorer.port
* integer
* The port number of the blockchain explorer service.

### explorer.reset
* true/false
* This variable controls if we want to reset the blockchain explorer server before running the benchnmark test.

## parallel
* integer
* This defines how many parallel command we want to run to talk to the nodes. 100 means the script will send commands to 100 nodes in parallel.
Too high the number may clog the machine running the benchmark script. Too low the number may result in slower execution of the commands.

## userdata
* string
* The userdata file we used on each VM. The -http version is the new one use used to control soldier via REST api.

## flow
This section defines flow contorl of the benchmark script.

### flow.wait_for_launch
* integer
* The time (seconds) wait for all the instance ready after launch.

# Sample
[benchmark-devnet.json](https://github.com/harmony-one/experiment-deploy/blob/master/configs/benchmark-devnet.json)
