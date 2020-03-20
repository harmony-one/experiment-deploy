#!/usr/bin/env python3
"""
This is a script to fund accounts without the use of an endpoint.

Note that this script assumes that the faucet key is in the CLI's keystore.

Example usage:
    python3 fund.py --amount 100000 --check --shards "0, 2, 3" 
"""

import json
import random
import time
import argparse
import os
import csv
from multiprocessing.pool import ThreadPool
from decimal import Decimal

from pyhmy import (
    cli,
    util
)
import pyhmy
import requests

faucet_addr = "one1zksj3evekayy90xt4psrz8h6j2v3hla4qwz4ur"  # Assumes that this is in the CLI's keystore.
# From: https://docs.google.com/spreadsheets/d/1Z5Jsf_wPkCKWrzYfSUApMFyBZy9Ye9EKBEb_-C89pYQ/edit#gid=0
accounts = [
    "one1kvfsza4u4e5ml6qv92j2pmsal2am9mcv9u4g83",
    "one1ujljr2nuymtxm0thjm32f64xsa9uzs54swreyw",
    "one1kvfsza4u4e5ml6qv92j2pmsal2am9mcv9u4g83",
    "one1p5hv9qv90dyrag9fj3wzrvvrs273ypcq8mz7zn",
    "one1egemh5e9xjy3x8d3cq0kq7mw4sw4jjwgkc7axs",
    "one1y5n7p8a845v96xyx2gh75wn5eyhtw5002lah27",
    "one10qq0uqa4gvgdufqjph89pp7nj6yeatz94xdjrt",
    "one1j33qtvx86j4ugy0a8exwwhtldm5wv4daksrwsl",
    "one1fv5ku7szkm60h4j4tcd2yanvjaw2ym3ugnls33",
    "one1rcv3chw86tprvhpw4fjnpy2gnvqy4gp4fmhdd9",
    "one1qyvwqh6klj2cfnzk4mcrlwae3790dm33jgy6kw",
    "one19gr02mxulyatwz4lpuhl2z3pezwx62xg2uchtg",
    "one1t0x76npc295gpsv64xzyf3qk9zml7a099v4cqj",
    "one1k7hgd27qggp8wcmn7n5u9sdhrjy7d2ed3m3c75",
    "one1xw94y2z7uc2qynyumze2ps8g4nq2w2qtzmdn8r",
    "one18vn078vyp5jafma8q7kek6w0resrgex9yufqws",
    "one1tpxl87y4g8ecsm6ceqay49qxyl5vs94jjyfvd9",
    "one103q7qe5t2505lypvltkqtddaef5tzfxwsse4z7",
    "one18jcl4uxjadq3qm3fj0clct3svugfxdkqy7f27s",
    "one1tewvfjk0d4whmajpqvcvzfpx6wftrh0gagsa7n",
    "one18xfcqu7jf0cq5apweyu5jxr30x9cvetegwqfss",
    "one1tnnncpjdqdjyk7y4d9gaxrg9qk927ueqptmptz",
    "one1337twjy8nfcwxzjqrc6lgqxxhs0zeult242ttw",
    "one15ap4frdwexw2zcue4hq5jjad5jjzz678urwkyw",
    "one12sujm2at8j8terh7nmw2gnxtrmk74wza3tvjd9",
    "one1wxlm29z9u08udhwuulgssnnh902vh9wfnt5tyh",
    "one1m4f8qng3h0lad30kygyr9c6nwsxpzehxm9av93",
    "one1m6j80t6rhc3ypaumtsfmqwjwp0mrqk9ff50prh",
    "one10fjqteq6q75nm62cx8vejqsk7mc8t5hle8ewnl",
    "one1vzsj3julf0ljcj3hhxuqpu6zvadu488zfrtttz",
    "one1marnnvc8hywmfxhrc8mtpjkvvdt32x9kxtwkvv",
    "one1xmx3fd69jp06ad23ptsj2pxuy2vsquhha76w0a",
    "one13upa4q2ntl4rjawrw2tjtj8n347yud0kv5eqk2",
    "one164e2dwupqxd7ssr85ncnkx3quk7fexy0eta2vy",
    "one1zc4et7xmtp8lna54ucye9phxlvw73kfgqeh5um"
]


def parse_args():
    parser = argparse.ArgumentParser(description='Funding script for a new network')
    parser.add_argument("--timeout", dest="timeout", default=120, help="timeout for each transaction")
    parser.add_argument("--amount", dest="amount", default="1000", type=str, help="Amount to fund each account")
    parser.add_argument("--accounts", dest="accounts", default=None, help="String in CSV format of one1... addresses")
    parser.add_argument("--shards", dest="shards", default=None,
                        help="String in CSV format of shards to fund, default is all.")
    parser.add_argument("--check", action="store_true", help="Spot check balances after funding")
    parser.add_argument("--force", action="store_true", help="Send transactions even if network appears to be offline")
    parser.add_argument("--yes", action="store_true", help="Say yes to profile check")
    parser.add_argument("--from_csv", dest="csv", help="Path to CSV file of keys, i.e: (harmony.one/keys2). "
                                                       "Note the file format assumption. "
                                                       "If given, the `amount` and `accounts` options are ignored. ",
                        default=None)
    p_arg = parser.parse_args()
    p_arg.accounts = accounts if p_arg.accounts is None else [el.strip()
                                                              for el in p_arg.accounts.split(",")
                                                              if el.strip()]
    return p_arg


def setup():
    assert hasattr(pyhmy, "__version__")
    assert pyhmy.__version__.major == 20, "wrong pyhmy version"
    assert pyhmy.__version__.minor == 1, "wrong pyhmy version"
    assert pyhmy.__version__.micro >= 14, "wrong pyhmy version, update please"
    env = cli.download("./bin/hmy", replace=False)
    cli.environment.update(env)
    cli.set_binary("./bin/hmy")


def get_balance(address, endpoint):
    url = endpoint
    payload = json.dumps({"id": "1", "jsonrpc": "2.0",
                          "method": "hmy_getBalance",
                          "params": [address, "latest"]})
    headers = {
        'Content-Type': 'application/json'
    }
    response = requests.request('POST', url, headers=headers, data=payload, allow_redirects=False, timeout=30)
    atto_bal = int(json.loads(response.content)["result"], 16)
    return float(Decimal(atto_bal) / Decimal(1e18))


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


def fund(shard, data=None):
    if not data:
        return fund_from_param(shard)
    return fund_from_csv_data(shard, data)


def fund_from_param(shard):
    if shard >= len(endpoints):
        return
    transactions = []
    nonce = get_nonce(endpoints[shard], faucet_addr)
    print(f"{util.Typgpy.HEADER}Preparing transactions for shard {shard} "
          f"({len(args.accounts)} transaction(s)){util.Typgpy.ENDC}")
    for acc in args.accounts:
        fund_amount = float(args.amount) - get_balance(acc, endpoints[shard])  # WARNING: Always fund the difference.
        if fund_amount > 0:
            transactions.append({
                "from": faucet_addr,
                "to": acc,
                "from-shard": str(shard),
                "to-shard": str(shard),
                "passphrase-string": "",
                "amount": str(fund_amount),
                "nonce": str(nonce),
            })
            nonce += 1
    filename = f"./fund-{os.environ['HMY_PROFILE']}.s{shard}.json"
    with open(filename, 'w') as f:
        json.dump(transactions, f, indent=4)
    command = f"hmy --node={endpoints[shard]} transfer --file {filename} --chain-id {chain_id} --timeout 0"
    if transactions:
        print(f"{util.Typgpy.HEADER}Sending {len(transactions)} transaction(s) on shard {shard}!{util.Typgpy.ENDC}")
        try:
            print(f"{util.Typgpy.HEADER}Transaction for shard {shard}:\n{util.Typgpy.OKGREEN}"
                  f"{cli.single_call(command, timeout=int(args.timeout) * len(endpoints) * len(args.accounts))} "
                  f"{util.Typgpy.ENDC}")
        except Exception as e:
            print(f"{util.Typgpy.FAIL}Transaction error: {e}{util.Typgpy.ENDC}")
    else:
        print(f"{util.Typgpy.FAIL}No transactions to send on shard {shard}!{util.Typgpy.ENDC}")


# TODO: generalize funding code to remove code duplication
def fund_from_csv_data(shard, data):
    if shard >= len(endpoints):
        return
    transactions = []
    nonce = get_nonce(endpoints[shard], faucet_addr)
    print(f"{util.Typgpy.HEADER}Preparing transactions for shard {shard} "
          f"({len(args.accounts)} transaction(s)){util.Typgpy.ENDC}")
    for dat in data:
        fund_amount = float(dat['amount']) - get_balance(dat['address'], endpoints[shard])  # WARNING: Always fund the difference.
        if fund_amount > 0:
            transactions.append({
                "from": faucet_addr,
                "to": dat['address'],
                "from-shard": str(shard),
                "to-shard": str(shard),
                "passphrase-string": "",
                "amount": str(fund_amount),
                "nonce": str(nonce),
            })
            nonce += 1
    filename = f"./fund-{os.environ['HMY_PROFILE']}.s{shard}.json"
    with open(filename, 'w') as f:
        json.dump(transactions, f, indent=4)
    command = f"hmy --node={endpoints[shard]} transfer --file {filename} --chain-id {chain_id} --timeout 0"
    if transactions:
        print(f"{util.Typgpy.HEADER}Sending {len(transactions)} transaction(s) on shard {shard}!{util.Typgpy.ENDC}")
        try:
            print(f"{util.Typgpy.HEADER}Transaction for shard {shard}:\n{util.Typgpy.OKGREEN}"
                  f"{cli.single_call(command, timeout=int(args.timeout) * len(endpoints) * len(args.accounts))} "
                  f"{util.Typgpy.ENDC}")
        except Exception as e:
            print(f"{util.Typgpy.FAIL}Transaction error: {e}{util.Typgpy.ENDC}")
    else:
        print(f"{util.Typgpy.FAIL}No transactions to send on shard {shard}!{util.Typgpy.ENDC}")


def parse_csv():
    data = []
    if args.csv is not None:
        with open(args.csv, 'r') as f:
            for row in csv.DictReader(f):
                raw_amount, raw_address = row['funded'], row['validator address']  # WARNING: Assumption of column name of CSV
                if raw_amount and 'one1' in raw_address:
                    data.append({
                        'amount': float(raw_amount.strip().replace(',', '')),
                        'address': raw_address.strip()
                    })
    return data


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
    if len(args.accounts) == 0:
        print(f"{util.Typgpy.HEADER}No accounts to fund...{util.Typgpy.ENDC}")
        exit()
    setup()
    assert cli.get_accounts(faucet_addr), f"`{faucet_addr}` is not found in CLI's keystore"
    net_config = get_network_config()
    chain_id = get_chain_id(net_config)
    endpoints = get_endpoints(net_config)
    args.shards = [i for i in range(len(endpoints))] if args.shards is None else [int(i.strip()) for i in
                                                                                  args.shards.split(",")]
    if not args.force:
        for ep in endpoints:
            assert util.is_active_shard(ep, delay_tolerance=120), f"`{ep}` is not an active endpoint"
    if os.environ['HMY_PROFILE'] is None:
        raise RuntimeError(f"{util.Typgpy.FAIL}Profile is not set, exiting...{util.Typgpy.ENDC}")

    csv_data = parse_csv()
    print(f"{util.Typgpy.HEADER}Funding using endpoints: {util.Typgpy.OKGREEN}{endpoints}{util.Typgpy.ENDC}")
    print(f"{util.Typgpy.HEADER}Funding on shards: {util.Typgpy.OKGREEN}{args.shards}{util.Typgpy.ENDC}")
    print(f"{util.Typgpy.HEADER}Chain-ID: {util.Typgpy.OKGREEN}{chain_id}{util.Typgpy.ENDC}")
    print(f"{util.Typgpy.HEADER}Profile: {util.Typgpy.OKGREEN}{os.environ['HMY_PROFILE']}{util.Typgpy.ENDC}")
    if csv_data:
        print(f"{util.Typgpy.HEADER}Funding from CSV: {util.Typgpy.OKGREEN}{args.csv}{util.Typgpy.ENDC}")
    else:
        print(f"{util.Typgpy.HEADER}Amount to fund per shard: {util.Typgpy.OKGREEN}{args.amount}{util.Typgpy.ENDC}")
        print(f"{util.Typgpy.HEADER}Count of accounts to fund: {util.Typgpy.OKGREEN}"
              f"{len(args.accounts)}{util.Typgpy.ENDC}")

    if not args.yes and input("Fund accounts?\n[Y]/n > ") != 'Y':
        exit()

    print("")
    pool = ThreadPool(processes=len(endpoints))
    shard_iter = iter(args.shards)
    threads = []

    try:
        while True:
            threads.clear()
            for _ in range(os.cpu_count()):
                i = next(shard_iter)
                threads.append(pool.apply_async(fund, (i, csv_data)))
            for t in threads:
                t.get()
    except StopIteration:
        for t in threads:
            t.get()
        threads.clear()

    print(f"{util.Typgpy.HEADER}Finished sending transactions!{util.Typgpy.ENDC}")
    if args.check:
        if csv_data:
            check_data = random.sample(csv_data, max(len(csv_data) // 10, 1))
        else:
            check_data = []
            for addr in random.sample(args.accounts, max(len(args.accounts) // 10, 1)):
                check_data.append({
                    'amount': args.amount,
                    'address': addr
                })
        print(f"{util.Typgpy.HEADER}Sleeping 60 seconds before checking balances{util.Typgpy.ENDC}")
        time.sleep(60)
        print(f"{util.Typgpy.HEADER}Spot checking {len(check_data)} balances....{util.Typgpy.ENDC}")
        failed = False
        for dat in check_data:
            for bal in get_balance_from_node_ip(dat['address'], endpoints):
                if int(bal["shard"]) in args.shards and float(bal["amount"]) < float(dat["amount"]):
                    print(f"{util.Typgpy.FAIL}{dat['address']} did not get funded!{util.Typgpy.ENDC}")
                    failed = True
                    break
        if not failed:
            print(f"{util.Typgpy.HEADER}Successfully checked {len(check_data)} balances....{util.Typgpy.ENDC}")
        else:
            exit(-1)
