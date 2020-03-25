#!/usr/bin/env python3
"""
This is a script to check BLS related information for a test network.

Example usage:
    python3 bls.py diff --shard 0
"""


import json
import argparse
import os
import math

from pyhmy import (
    util
)
import requests

from fund import (
    get_network_config,
    get_endpoints,
)

env = os.environ.copy()


def parse_args():
    parser = argparse.ArgumentParser(description='Network BLS information')
    parser.add_argument("command", help="What BLS key function to do on network. Supported commands:\n\n"
                                        "\t`ref`  \tGet reference/configured BLS keys per node for network.\n\n"
                                        "\t`dist` \tGet current distribution of bls keys with IP address.\n\n"
                                        "\t`diff` \tGet missing BLS keys per node for network.\n\n")
    parser.add_argument("--shard", default=None, help="Specify a shard for a command", type=int)
    parser.add_argument("--raw", action="store_true", help="Disable pretty printing")
    return parser.parse_args()


def get_metadata(endpoint):
    url = endpoint
    payload = json.dumps({"id": "1", "jsonrpc": "2.0",
                          "method": "hmy_getNodeMetadata",
                          "params": []})
    headers = {
        'Content-Type': 'application/json'
    }
    response = requests.request('POST', url, headers=headers, data=payload, allow_redirects=False, timeout=30)
    return json.loads(response.content)["result"]


def get_bls_keys_on_node(endpoint):
    """
    WARNING: This is subject to change in the future
    """
    try:
        metadata = get_metadata(endpoint)
    except Exception:  # Do not halt on any exception
        return None
    bls_key_len = 96
    bls_keys = metadata["blskey"]
    return [bls_keys[i*bls_key_len:(i+1)*bls_key_len] for i in range(len(bls_keys)//bls_key_len)]


def get_bls_distribution(shard):
    """
    Assumes that this is executed on a machine that has access to internal nodes.
    """
    distribution = []
    log_dir = f"{os.path.dirname(os.path.realpath(__file__))}/logs/{os.environ['HMY_PROFILE']}"
    assert os.path.isdir(log_dir)
    shard_log_path = f"{log_dir}/shard{shard}.txt"
    assert os.path.isfile(shard_log_path)
    with open(shard_log_path, 'r') as f:
        ip_list = f.readlines()
    for ip in ip_list:
        ip = ip.strip()
        if ip:
            distribution.append({
                'ip': ip,
                'bls-keys': get_bls_keys_on_node(f"http://{ip}:9500/")
            })
    return distribution


def get_all_test_keys():
    with open(f'{os.path.dirname(os.path.realpath(__file__))}/../configs/blskey-test.txt', 'r') as f:
        return [x for x in f.read().split('\n') if x]


def get_stride(config):
    if "multikey" not in config:
        return 1
    benchmark_config = config['benchmark']
    keys_per_shard = benchmark_config['peer_per_shard']
    keys_per_node = config['multikey']['keys_per_node']
    nodes_per_shard = math.ceil(keys_per_shard / keys_per_node)
    return int(nodes_per_shard * benchmark_config['shards'])


def get_total_keys(config):
    stride = get_stride(config)
    keys_per_node = config['multikey']['keys_per_node']
    return stride * keys_per_node


def get_all_reference_keys(config):
    """
    Returns a 2d array where the rows are machines and the columns are keys
    """
    stride = get_stride(config)
    test_keys = get_all_test_keys()
    keys_per_node = config['multikey']['keys_per_node']
    keys = []
    for i in range(stride):
        lst = []
        for j in range(i, stride*keys_per_node, stride):
            lst.append(test_keys[j].replace(".key", ""))
        keys.append(lst)
    return keys


def handle_ref():
    ref_key = get_all_reference_keys(config)
    if args.shard is not None:
        shard_count = config['benchmark']['shards']
        shard_ref_key = []
        for i, lst in enumerate(ref_key):
            if i % shard_count == args.shard:
                shard_ref_key.append(lst)
        ref_key = shard_ref_key
    if args.raw:
        print(ref_key)
    else:
        for i, row in enumerate(ref_key):
            print(f"Machine {i}")
            for el in row:
                print(f"\t{el}")


def handle_dst():
    def handle(shard):
        dist = get_bls_distribution(shard)
        if args.raw:
            print(dist)
        else:
            for d in dist:
                print(f"Shard {shard}: {d['ip']}")
                if d['bls-keys'] is None:
                    print("\tUnable to get BLS key(s)")
                elif not d['bls-keys']:
                    print("\tNo BLS key(s)")
                else:
                    for el in d['bls-keys']:
                        print(f"\t{el}")
            print("")

    if args.shard is not None:
        handle(args.shard)
    else:
        for s in range(int(config['benchmark']['shards'])):
            handle(s)


def handle_diff():
    ref_key = get_all_reference_keys(config)
    shard_count = config['benchmark']['shards']

    def handle(shard):
        missing = []
        dist = get_bls_distribution(shard)
        present_keys = set()
        for d in dist:
            if d['bls-keys'] is not None:
                for k in d['bls-keys']:
                    present_keys.add(k)
        for i, lst in enumerate(ref_key):
            if i % shard_count == shard:
                for k in lst:
                    if k not in present_keys:
                        if not all(x not in present_keys for x in lst):
                            print(f"{util.Typgpy.FAIL}Keys in group: {lst} were not distributed properly.{util.Typgpy.ENDC}")
                        missing.append(lst)
                        break

        if args.raw:
            print(missing)
        else:
            if not missing:
                print(f"Shard {shard}: No BLS key is missing!")
            else:
                for i, row in enumerate(missing):
                    print(f"Shard {shard}: Missing machine {i}")
                    for el in row:
                        print(f"\t{el}")
            print("")

    if args.shard is not None:
        handle(args.shard)
    else:
        for s in range(int(config['benchmark']['shards'])):
            handle(s)


if __name__ == "__main__":
    if os.environ['HMY_PROFILE'] is None:
        raise RuntimeError(f"{util.Typgpy.FAIL}Profile is not set, exiting...{util.Typgpy.ENDC}")
    args = parse_args()
    config = get_network_config()
    endpoints = get_endpoints(config)
    if args.command == "ref":
        handle_ref()
    elif args.command == "dist":
        handle_dst()
    elif args.command == "diff":
        handle_diff()
    else:
        print(f"{util.Typgpy.FAIL}Unknown argument...{util.Typgpy.ENDC}")
        exit(-1)

