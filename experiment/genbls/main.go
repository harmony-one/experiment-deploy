package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"math"
	"os"
	"path"

	"github.com/harmony-one/experiment-deploy/experiment/genesis"
)

var (
	version string
	builtBy string
	builtAt string
	commit  string
)

func printVersion(me string) {
	fmt.Fprintf(os.Stderr, "Harmony (C) 2020. %v, version %v-%v (%v %v)\n", path.Base(me), version, commit, builtBy, builtAt)
	os.Exit(0)
}

// gen_bls_key generates an 3-d array
// 1d is the shard
// 2d is the node in each shard
// 3d is the keys per node
func gen_bls_key(shard int, slot int, key int) (shard_keys [][][]int, nodes int) {
	// generate key list
	shard_keys = make([][][]int, shard)

	max_key := shard * slot
	var num_node int
	for s := 0; s < shard; s++ {
		num_node = int(math.Ceil(float64(slot) / float64(key)))
		shard_keys[s] = make([][]int, num_node)
		for i := 0; i < num_node; i++ {
			shard_keys[s][i] = make([]int, key)

			for k := 0; k < key; k++ {
				index := s + i*shard + k*shard*num_node
				if index < max_key {
					shard_keys[s][i][k] = index
				}
			}
		}
	}

	return shard_keys, shard * num_node
}

// generate ansible configuration file in yaml format
func gen_ansible_config(keys [][][]int, network string) {
	var accounts []genesis.DeployAccount

	switch network {
	case "mainnet":
		accounts = genesis.HarmonyAccounts
	case "testnet":
		accounts = genesis.TNHarmonyAccounts
	default:
		fmt.Printf("unknown network type: %v\n", network)
	}
	for s, shard := range keys {
		fmt.Printf("shard: %v\n", s)
		for n, node := range shard {
			fmt.Printf("node%v:\n", n)
			for _, index := range node {
				blskey := accounts[index].BLSPublicKey
				fmt.Printf("%v\t%v\n", index, blskey)
			}
		}
	}
}

// parse the host json file
// format is an array of host IP,
// Ex, [ "1.2.3.4", "2.3.4.5" ]
func parse_host_json(hostfile string) (hosts []string) {
	data, err := ioutil.ReadFile(hostfile)
	if err != nil {
		log.Fatal(err)
		return nil
	}

	if err := json.Unmarshal(data, &hosts); err != nil {
		log.Fatal(err)
		return nil
	}
	return hosts
}

func main() {
	shard := flag.Int("shard", 4, "number of shard")
	slot := flag.Int("slot", 170, "number of slot per shard")
	key := flag.Int("key", 10, "number of keys per node")
	versionFlag := flag.Bool("version", false, "Output version info")
	network := flag.String("network", "mainnet", "type of network: mainnet/testnet")
	hostfile := flag.String("host", "", "json file of the hosts IP")

	flag.Parse()

	if *versionFlag {
		printVersion(os.Args[0])
	}

	hosts := parse_host_json(*hostfile)
	shard_keys, total_nodes := gen_bls_key(*shard, *slot, *key)

	if len(hosts) < total_nodes {
		fmt.Printf("Not enough hosts: %d provided, %d required\n", len(hosts), total_nodes)
		os.Exit(1)
	}

	gen_ansible_config(shard_keys, *network)
}
