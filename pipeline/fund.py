#!/usr/bin/env python3
"""
This is a script to fund accounts without the use of an endpoint.

Note that this script assumes that the faucet key is in the CLI's keystore.

Example usage:
    python3 fund.py --amount 100000 --check
"""

import json
import random
import time
import argparse
import os
from multiprocessing.pool import ThreadPool

from pyhmy import (
    cli,
    util
)
import pyhmy
import requests

faucet_addr = "one1zksj3evekayy90xt4psrz8h6j2v3hla4qwz4ur"  # Assumes that this is in the CLI's keystore.
# From: https://docs.google.com/spreadsheets/d/1Z5Jsf_wPkCKWrzYfSUApMFyBZy9Ye9EKBEb_-C89pYQ/edit#gid=0
accounts = [
    "one1kvfsza4u4e5ml6qv92j2pmsal2am9mcv9u4g83"
    "one1ujljr2nuymtxm0thjm32f64xsa9uzs54swreyw"
    "one1p5hv9qv90dyrag9fj3wzrvvrs273ypcq8mz7zn"
    "one1egemh5e9xjy3x8d3cq0kq7mw4sw4jjwgkc7axs"
    "one1y5n7p8a845v96xyx2gh75wn5eyhtw5002lah27"
    "one10qq0uqa4gvgdufqjph89pp7nj6yeatz94xdjrt"
    "one1j33qtvx86j4ugy0a8exwwhtldm5wv4daksrwsl"
    "one1fv5ku7szkm60h4j4tcd2yanvjaw2ym3ugnls33"
    "one1rcv3chw86tprvhpw4fjnpy2gnvqy4gp4fmhdd9"
    "one1wh4p0kuc7unxez2z8f82zfnhsg4ty6dupqyjt2"
    "one19gr02mxulyatwz4lpuhl2z3pezwx62xg2uchtg"
    "one1t0x76npc295gpsv64xzyf3qk9zml7a099v4cqj"
    "one1k7hgd27qggp8wcmn7n5u9sdhrjy7d2ed3m3c75"
    "one1sdzeclwvcjxkvjehpagh0fgs8cxtf73q4leysz"
    "one1tpxl87y4g8ecsm6ceqay49qxyl5vs94jjyfvd9"
    "one1tnnncpjdqdjyk7y4d9gaxrg9qk927ueqptmptz"
    "one1337twjy8nfcwxzjqrc6lgqxxhs0zeult242ttw"
    "one15ap4frdwexw2zcue4hq5jjad5jjzz678urwkyw"
    "one1wxlm29z9u08udhwuulgssnnh902vh9wfnt5tyh"
    "one1m6j80t6rhc3ypaumtsfmqwjwp0mrqk9ff50prh"
    "one10fjqteq6q75nm62cx8vejqsk7mc8t5hle8ewnl"
    "one1vzsj3julf0ljcj3hhxuqpu6zvadu488zfrtttz"
    "one1marnnvc8hywmfxhrc8mtpjkvvdt32x9kxtwkvv"
    "one1u6c4wer2dkm767hmjeehnwu6tqqur62gx9vqsd"
    "one1t4p6x5k7zw59kers7hwmjh3kymj0n6spr02qnf"
    "one1s7fp0jrmd97estwye3mhkp7xsqf42vn5x2sfqy"
    "one10jvjrtwpz2sux2ngktg3kq7m3sdz5p5au5l8c8"
    "one1km7xg8e3xjys7azp9f4xp8hkw79vm2h3f2lade"
    "one1c9h3u72czs6sk755tjyse7x5t70m38ppnkx922"
    "one170xqsfzm4xdmuyax54t5pvtp5l5yt66u50ctrp"
    "one1vfqqagdzz352mtvdl69v0hw953hm993n6v26yl"
    "one1gjsxmewzws9mt3fn65jmdhr3e4hel9xza8wd6t"
    "one1mpzx5wr2kmz9nvkhsgj6jr6zs87ahm0gxmhlck"
]


def parse_args():
    parser = argparse.ArgumentParser(description='Funding script for a new network')
    parser.add_argument("--timeout", dest="timeout", default=120, help="timeout for each transaction")
    parser.add_argument("--amount", dest="amount", default="1000", type=str, help="Amount to fund each account")
    parser.add_argument("--accounts", dest="accounts", default=None, help="String in CSV format of one1... addresses")
    parser.add_argument("--check", action="store_true", help="Spot check balances after funding")
    parser.add_argument("--force", action="store_true", help="Send transactions even if network appears to be offline")
    p_arg = parser.parse_args()
    p_arg.accounts = accounts if p_arg.accounts is None else [el.strip() for el in p_arg.accounts.split(",")]
    return p_arg


def setup():
    assert hasattr(pyhmy, "__version__")
    assert pyhmy.__version__.major == 20, "wrong pyhmy version"
    assert pyhmy.__version__.minor == 1, "wrong pyhmy version"
    assert pyhmy.__version__.micro >= 14, "wrong pyhmy version, update please"
    env = cli.download("./bin/hmy", replace=True)
    cli.environment.update(env)
    cli.set_binary("./bin/hmy")


def get_nonce(endpoint, address):
    url = endpoint
    payload = "{\"jsonrpc\": \"2.0\", \"method\": \"hmy_getTransactionCount\"," \
              "\"params\": [\"" + address + "\", \"latest\"],\"id\": 1}"
    headers = {
        'Content-Type': 'application/json'
    }
    response = requests.request('POST', url, headers=headers, data=payload, allow_redirects=False, timeout=30)
    return int(json.loads(response.content)["result"], 16)


def get_network_config():
    """
    Strong assumption made about where config is and what it is named.
    """
    config_path = f"{os.path.dirname(os.path.realpath(__file__))}/../configs/benchmark-{os.environ['HMY_PROFILE']}.json"
    assert os.path.isfile(config_path), f"`{config_path}` does not exist!"
    with open(config_path, 'r') as f:
        return json.load(f)


def get_chain_id(config):
    assert "benchmark" in config
    benchmark = config["benchmark"]
    return benchmark["network_type"] if "network_type" in benchmark.keys() else "testnet"


def get_endpoints(config):
    """
    Strong assumption made about where network logs get put after network init.
    """
    assert "benchmark" in config
    assert "shards" in config["benchmark"]
    eps = []
    num_shards = int(config["benchmark"]["shards"])
    shard_log_files = [f"shard{j}.txt" for j in range(num_shards)]
    log_dir = f"{os.path.dirname(os.path.realpath(__file__))}/logs/{os.environ['HMY_PROFILE']}"
    assert os.path.isdir(log_dir)
    for shard_file in shard_log_files:
        shard_log_path = f"{log_dir}/{shard_file}"
        assert os.path.isfile(shard_log_path)
        with open(shard_log_path, 'r') as f:
            ip_list = f.readlines()
        assert len(ip_list) > 0
        eps.append(f"http://{ip_list[0].strip()}:9500/")
    return eps


def fund(shard):
    if shard >= len(endpoints):
        return
    transactions = []
    starting_nonce = get_nonce(endpoints[shard], faucet_addr)
    print(f"{util.Typgpy.HEADER}Sending funds for shard {shard} ({len(args.accounts)} transaction(s)){util.Typgpy.ENDC}")
    for j, acc in enumerate(args.accounts):
        transactions.append({
            "from": faucet_addr,
            "to": acc,
            "from-shard": str(shard),
            "to-shard": str(shard),
            "passphrase-string": "",
            "amount": str(args.amount),
            "nonce": str(starting_nonce + j),
        })
    filename = f"./fund-{os.environ['HMY_PROFILE']}.s{shard}.json"
    with open(filename, 'w') as f:
        json.dump(transactions, f, indent=4)
    command = f"hmy --node={endpoints[shard]} transfer --file {filename} --chain-id {chain_id} --timeout 0"
    print(f"{util.Typgpy.HEADER}Transaction for shard {shard}:\n{util.Typgpy.OKGREEN}"
          f"{cli.single_call(command, timeout=int(args.timeout) * len(endpoints) * len(args.accounts))} "
          f"{util.Typgpy.ENDC}")


def get_balance_from_node_ip(address, endpoint_list):
    """
    Assumes that endpoints provided are ips and that the CLI
    only returns the balances for a specific shard.
    """
    balances = []
    for endpoint in endpoint_list:
        cli_bal = json.loads(cli.single_call(f"hmy --node={endpoint} balances {address}"))
        assert len(cli_bal) == 1, f"Expect CLI to only return balances for 1 shard. Got: {cli_bal}"
        balances.append(cli_bal[0])
    return balances


if __name__ == "__main__":
    args = parse_args()
    setup()
    assert cli.get_accounts(faucet_addr), f"`{faucet_addr}` is not found in CLI's keystore"
    net_config = get_network_config()
    chain_id = get_chain_id(net_config)
    endpoints = get_endpoints(net_config)
    if not args.force:
        for ep in endpoints:
            assert util.is_active_shard(ep, delay_tolerance=120), f"`{ep}` is not an active endpoint"
    if os.environ['HMY_PROFILE'] is None:
        raise RuntimeError(f"{util.Typgpy.FAIL}Profile is not set, exiting...{util.Typgpy.ENDC}")

    print(f"{util.Typgpy.HEADER}Funding using endpoints: {util.Typgpy.OKGREEN}{endpoints}{util.Typgpy.ENDC}")
    print(f"{util.Typgpy.HEADER}Chain-ID: {util.Typgpy.OKGREEN}{chain_id}{util.Typgpy.ENDC}")
    print(f"{util.Typgpy.OKBLUE}Profile: {util.Typgpy.OKGREEN}{os.environ['HMY_PROFILE']}{util.Typgpy.ENDC}")
    if input("Fund accounts?\n[Y]/n > ") != 'Y':
        exit()

    pool = ThreadPool(processes=len(endpoints))
    i = 0
    while i < len(endpoints):
        threads = []
        for _ in range(os.cpu_count()):
            threads.append(pool.apply_async(fund, (i,)))
            i += 1
            if i >= len(endpoints):
                break
        for t in threads:
            t.get()

    print(f"{util.Typgpy.HEADER}Finished sending transactions!{util.Typgpy.ENDC}")
    if args.check:
        print(f"{util.Typgpy.HEADER}Sleeping 90 seconds before checking balances{util.Typgpy.ENDC}")
        time.sleep(90)
        addrs_to_check = random.sample(args.accounts, max(len(args.accounts) // 10, 1))
        print(f"{util.Typgpy.HEADER}Spot checking {len(addrs_to_check)} balances....{util.Typgpy.ENDC}")
        failed = False
        for addr in addrs_to_check:
            for bal in get_balance_from_node_ip(addr, endpoints):
                if float(bal["amount"]) < float(args.amount):
                    print(f"{util.Typgpy.FAIL}{addr} did not get funded!{util.Typgpy.ENDC}")
                    failed = True
                    break
        if not failed:
            print(f"{util.Typgpy.HEADER}Successfully checked {len(addrs_to_check)} balances....{util.Typgpy.ENDC}")
        else:
            exit(-1)
