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

var (
	PassFile string
	KeyPath  string
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

// copy_bls_key will copy the blskey file and pass file to the dest directory
func copy_bls_key(key string, dest string) error {
	keyname := fmt.Sprintf("%v.key", key)
	passname := fmt.Sprintf("%v.pass", key)

	keyfile := path.Join(KeyPath, keyname)
	destkey := path.Join(dest, keyname)
	destpass := path.Join(dest, passname)

	if err := os.Link(keyfile, destkey); err != nil {
		return err
	}
	if err := os.Link(PassFile, destpass); err != nil {
		return err
	}

	return nil
}

// generate ansible files/<host>/bls.key directories/files based on blskey distribution
func gen_ansible_config(keys [][][]int, network string, hosts []string) {
	var accounts []genesis.DeployAccount

	switch network {
	case "mainnet":
		accounts = genesis.HarmonyAccounts
	case "testnet":
		accounts = genesis.TNHarmonyAccounts
	default:
		fmt.Printf("unknown network type: %v\n", network)
	}
	os.MkdirAll("files", os.ModeDir|0755)
	h := 0
	for s, shard := range keys {
		fmt.Printf("shard: %v\n", s)
		for n, node := range shard {
			fmt.Printf("node%v => %v\n", n, hosts[h])
			dest := path.Join("files", hosts[h])
			os.MkdirAll(dest, os.ModeDir|0755)
			for _, index := range node {
				blskey := accounts[index].BLSPublicKey
				if copy_bls_key(blskey, dest) != nil {
					fmt.Printf("failed to copy blskey: %v to node: %v", blskey, hosts[h])
				}
				h++
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

	flag.StringVar(&PassFile, "pass", "", "path to the bls.pass file")
	flag.StringVar(&KeyPath, "keypath", "", "directory of the bls keys")

	flag.Parse()

	if *versionFlag {
		printVersion(os.Args[0])
	}

	if _, err := os.Stat(PassFile); err != nil {
		fmt.Printf("wrong passfile: %v", err)
	}
	if _, err := os.Stat(KeyPath); err != nil {
		fmt.Printf("wrong key path: %v", err)
	}

	hosts := parse_host_json(*hostfile)
	shard_keys, total_nodes := gen_bls_key(*shard, *slot, *key)

	if len(hosts) < total_nodes {
		fmt.Printf("Not enough hosts: %d provided, %d required\n", len(hosts), total_nodes)
		os.Exit(1)
	}

	gen_ansible_config(shard_keys, *network, hosts)
}
