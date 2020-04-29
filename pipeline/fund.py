#!/usr/bin/env python3
"""
This is a script to fund accounts without the use of an endpoint.

Note that this script assumes that the faucet key is in the CLI's keystore.

Example usage:
    python3 fund.py --amount 100000 --shards "0, 2, 3"
"""

import json
import sys
import time
import argparse
import os
import csv
from multiprocessing.pool import ThreadPool
from threading import Lock
from decimal import Decimal

from pyhmy import (
    cli,
    util
)
import pyhmy
import requests

faucet_addr = "one1zksj3evekayy90xt4psrz8h6j2v3hla4qwz4ur"  # Assumes that this is in the CLI's keystore.
accounts = [
    "one17dcjcyauyr43rqh29sa9zeyvfvqc54yzuwyd64",
]
fund_log_lock = Lock()
fund_log = {
    "block-height": 0,
    "funded-accounts": {}
}


def parse_args():
    parser = argparse.ArgumentParser(description='Funding script for a new network')
    parser.add_argument("--timeout", dest="timeout", default=120, help="timeout for each transaction")
    parser.add_argument("--amount", dest="amount", default="1000", type=str, help="Amount to fund each account")
    parser.add_argument("--accounts", dest="accounts", default=None, help="String in CSV format of one1... addresses")
    parser.add_argument("--shards", dest="shards", default=None,
                        help="String in CSV format of shards to fund, default is all.")
    parser.add_argument("--force", action="store_true", help="Force send transactions, ignoring all checks")
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


def load_log():
    global fund_log
    log_dir = f"{os.path.dirname(os.path.realpath(__file__))}/logs/{os.environ['HMY_PROFILE']}"
    file = f"{log_dir}/funding.json"
    if os.path.isfile(file):
        with open(file, 'r') as f:
            loaded_fund_log = json.load(f)
        curr_height = json.loads(cli.single_call(f"hmy blockchain "
                                                 f"latest-header -n {endpoints[0]}"))["result"]["blockNumber"]
        if loaded_fund_log['block-height'] <= curr_height:
            fund_log = loaded_fund_log


def save_log():
    fund_log["block-height"] = json.loads(cli.single_call(f"hmy blockchain "
                                                          f"latest-header -n {endpoints[0]}"))["result"]["blockNumber"]
    log_dir = f"{os.path.dirname(os.path.realpath(__file__))}/logs/{os.environ['HMY_PROFILE']}"
    file = f"{log_dir}/funding.json"
    with open(file, 'w') as f:
        json.dump(fund_log, f, indent=4)


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
        fund_log_lock.acquire()
        if dat['address'] not in fund_log['funded-accounts'].keys():
            fund_log['funded-accounts'][dat['address']] = {str(i): 0 for i in range(len(endpoints))}
        balance_log = fund_log['funded-accounts'][dat['address']]
        fund_log_lock.release()
        fund_amount = float(args.amount) - balance_log[str(shard)]  # WARNING: Always fund the difference.
        if fund_amount > 0 or args.force:
            transactions.append({
                "from": faucet_addr,
                "to": acc,
                "from-shard": str(shard),
                "to-shard": str(shard),
                "passphrase-string": "",
                "amount": str(fund_amount) if fund_amount > 0 else str(args.amount),
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
          f"({len(data)} transaction(s)){util.Typgpy.ENDC}")
    for dat in data:
        fund_log_lock.acquire()
        if dat['address'] not in fund_log['funded-accounts'].keys():
            fund_log['funded-accounts'][dat['address']] = {str(i): 0 for i in range(len(endpoints))}
        balance_log = fund_log['funded-accounts'][dat['address']]
        fund_log_lock.release()
        fund_amount = float(dat['amount']) - balance_log[str(shard)]  # WARNING: Always fund the difference.
        balance = get_balance(dat['address'], endpoints[shard])
        if fund_amount > 0 and balance < fund_amount or args.force:
            transactions.append({
                "from": faucet_addr,
                "to": dat['address'],
                "from-shard": str(shard),
                "to-shard": str(shard),
                "passphrase-string": "",
                "amount": str(fund_amount) if fund_amount > 0 else str(dat['amount']),
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
                raw_amount, raw_address = row['funded'].strip(), row['validator address'].strip()
                if raw_address and raw_address.startswith('one1') and raw_amount:
                    sys.stdout.write(f"\rLoading address: {raw_address} to funding candidate from CSV.")
                    sys.stdout.flush()
                    try:
                        cli.single_call(f"hmy utility bech32-to-addr {raw_address}")
                        data.append({
                            'amount': float(raw_amount.replace(',', '')),
                            'address': raw_address
                        })
                    except Exception as e:  # catch all to not halt script
                        print(f"{util.Typgpy.FAIL}\nError when parsing CSV file (addr `{raw_address}`). {e}{util.Typgpy.ENDC}")
                        print(f"{util.Typgpy.WARNING}Skipping...{util.Typgpy.ENDC}")
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

    load_log()
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
    if csv_data:
        check_data = csv_data
    else:
        check_data = []
        for addr in args.accounts:
            check_data.append({
                'amount': args.amount,
                'address': addr
            })
    print(f"{util.Typgpy.HEADER}Sleeping 60 seconds before checking balances{util.Typgpy.ENDC}")
    time.sleep(60)
    print(f"{util.Typgpy.HEADER}Checking {len(check_data)} balances....{util.Typgpy.ENDC}")
    failed = False
    for j, dat in enumerate(check_data):
        fund_log_lock.acquire()
        if dat['address'] not in fund_log['funded-accounts'].keys():
            fund_log['funded-accounts'][dat['address']] = {str(i): 0 for i in range(len(endpoints))}
        balance_log = fund_log['funded-accounts'][dat['address']]
        fund_log_lock.release()
        for shard in args.shards:
            balance = get_balance(dat['address'], endpoints[int(shard)])
            print(json.dumps({
                'address': dat['address'],
                'balance': balance,
                'shard': int(shard)
            }))
            balance_log[shard] = max(balance_log[str(shard)], balance)
            save_log()
            if balance < float(dat["amount"]):
                print(f"{util.Typgpy.FAIL}{dat['address']} did not get funded on shard {shard}{util.Typgpy.ENDC}")
                failed = True
    if not failed:
        print(f"{util.Typgpy.HEADER}Successfully checked {len(check_data)} balances!{util.Typgpy.ENDC}")
