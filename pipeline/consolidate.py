#!/usr/bin/env python3
"""
This is a script to consolidate all given balances without the use of an endpoint.

Note that this takes a config JSON file to dictate which accounts to consolidate.
Each element of the JSON array represents 1 account's information.

Example of such config file:
    ```
    [
      {
        "keystore-file-path": "./test_keys/1.key",
        "passphrase-file-path": "./test_pw/1.pw"
      },
      {
        "keystore-file-path": "./test_keys/2.key",
        "passphrase": "test123"
      },
      {
        "private-key": "0336e9be71c31d71d086d9f0887d13cb6701bc45d11b70bb7c14200c9feebe22"
      },
      {
        "private-key": "6213bea7aef783463e67ed0c476a2915339de01f30658e7bb88ef5861e64b5e5"
      }
    ]
    ```

Fields for each element in the JSON array:
    +-----------------------+-----------------------------------------------------------------+
    |         Field         |                          Description                            |
    +-----------------------+-----------------------------------------------------------------+
    | keystore-file-path    | Path (absolute or relative) to the keystore file                |
    | passphrase-file-path  | Path (absolute or relative) to passphrase stored in plain text  |
    | passphrase            | Passphrase of file as a string                                  |
    | private-key           | Elliptic curve private key for account                          |
    +-----------------------------------------------------------------------------------------+
    Note: If no passphrase (path or string) is provided, an empty string is used.

Example usage:
    python3 consolidate.py one1zksj3evekayy90xt4psrz8h6j2v3hla4qwz4ur --config ./consolidate_test_funds.json --amount 2000 --check
"""

import json
import time
import sys
import shutil
import argparse
import os
from decimal import Decimal
from multiprocessing.pool import ThreadPool

from pyhmy import (
    cli,
    util
)

from fund import (
    setup,
    get_network_config,
    get_chain_id,
    get_endpoints,
    get_balance_from_node_ip,
)

prefix = "consolidation_"
added_key_names = []


def parse_args():
    parser = argparse.ArgumentParser(description='')
    parser.add_argument("dest_address", help="The Bech32 address of the account to send all the money to")
    parser.add_argument("--config", dest="config", default="consolidate_config.json",
                        help="path to the config file for this script (default is `consolidate_config.json`)")
    parser.add_argument("--timeout", dest="timeout", default=120, help="timeout for each transaction")
    parser.add_argument("--gas_price", dest="gas_price", default=1, help="Gas price for all transactions (default 1)")
    parser.add_argument("--gas_limit", dest="gas_limit", default=21000,
                        help="Gas limit for all transactions (default 21000)")
    parser.add_argument("--amount", dest="amount", help="Max amount to consolidate for each given account. Per shard. "
                                                        "Default is all funds.", default=None, type=float)
    parser.add_argument("--check", action="store_true", help="Spot check balances after transfers")
    parser.add_argument("--force", action="store_true", help="Send transactions even if network appears to be offline")
    return parser.parse_args()


def load_accounts():
    accs_info = []
    assert os.path.isfile(args.config), f"`{args.config}` is not a file"
    with open(args.config, 'r') as f:
        config = json.load(f)
    cli_dir = cli.get_account_keystore_path()
    for j, src_info in enumerate(config):
        sys.stdout.write(f"Key import progress: {j}/{len(config)}   \r")
        sys.stdout.flush()
        # Passphrase parsing
        if "passphrase-file-path" in src_info.keys():
            pw_path = src_info['passphrase-file-path']
            assert os.path.isfile(pw_path), f"`{pw_path}` is not a file."
            with open(pw_path, 'r') as f:
                passphrase = f.read().strip()
        elif "passphrase" in src_info.keys():
            passphrase = src_info['passphrase']
        else:
            passphrase = ''  # CLI default passphrase

        # Load key
        acc_name = f"{prefix}{j}"
        cli.remove_account(acc_name)
        if "keystore-file-path" in src_info.keys():
            ks_path = src_info['keystore-file-path']
            assert os.path.isfile(ks_path), f"`{ks_path}` is not a file."
            os.makedirs(f"{cli_dir}/{acc_name}")
            shutil.copy(ks_path, f"{cli_dir}/{acc_name}")
            address = cli.get_address(acc_name)
            if address is None:
                raise RuntimeError(f"Could not import key for config {j}")
            added_key_names.append(acc_name)
        elif "private-key" in src_info.keys():
            cli.single_call(f"hmy keys import-private-key {src_info['private-key']} {acc_name}")
            address = cli.get_address(acc_name)
            if address is None:
                raise RuntimeError(f"Could not import key for config {j}")
        else:
            raise RuntimeError(f"No key to import for config {j}")

        accs_info.append({
            'address': address,
            'passphrase': passphrase
        })
    return accs_info


def consolidate(shard):
    if shard >= len(endpoints):
        return
    transactions = []
    total_amt = 0
    overhead = Decimal(args.gas_price * args.gas_limit) * Decimal(1e-18) + Decimal(1e-18)
    max_amount = float('inf') if args.amount is None else Decimal(args.amount) + overhead
    print(f"{util.Typgpy.HEADER}Consolidating funds for shard {shard} ({len(accounts_info)} transaction(s)){util.Typgpy.ENDC}")
    for acc in accounts_info:
        acc_bal = json.loads(cli.single_call(f"hmy --node={endpoints[shard]} balances {acc['address']}"))[0]
        assert acc_bal["shard"] == shard, f"balance for shard {shard} does not match endpoint"
        amount = round(Decimal(min(acc_bal["amount"], max_amount)) - overhead, 18)
        total_amt += amount
        transactions.append({
            "from": acc['address'],
            "to": args.dest_address,
            "from-shard": str(shard),
            "to-shard": str(shard),
            "gas-price": str(args.gas_price),
            "gas-limit": str(args.gas_limit),
            "passphrase-string": acc['passphrase'],
            "amount": str(amount)
        })
    filename = f"./{prefix}fund{shard}.json"
    with open(filename, 'w') as f:
        json.dump(transactions, f, indent=4)
    command = f"hmy --node={endpoints[shard]} transfer --file {filename} --chain-id {chain_id} --timeout 0"
    print(f"{util.Typgpy.HEADER}Transaction for shard {shard}:\n{util.Typgpy.OKGREEN}"
          f"{cli.single_call(command, timeout=int(args.timeout) * len(endpoints) * len(accounts_info))}"
          f"{util.Typgpy.ENDC}")
    return total_amt


if __name__ == "__main__":
    args = parse_args()
    assert os.path.isfile(args.config), f"`{args.config}` is not a file."
    setup()
    net_config = get_network_config()
    chain_id = get_chain_id(net_config)
    endpoints = get_endpoints(net_config)
    if not args.force:
        for ep in endpoints:
            assert util.is_active_shard(ep, delay_tolerance=200), f"`{ep}` is not an active endpoint"
    if os.environ['HMY_PROFILE'] is None:
        raise RuntimeError("Profile is not set, exiting...")

    print(f"{util.Typgpy.BOLD}Importing keys{util.Typgpy.ENDC}")
    accounts_info = load_accounts()
    init_bal = 0
    for bal in get_balance_from_node_ip(args.dest_address, endpoints):
        init_bal += bal["amount"]

    print(f"{util.Typgpy.OKBLUE}Consolidating funds to: {util.Typgpy.OKGREEN}{args.dest_address}{util.Typgpy.ENDC}")
    print(f"{util.Typgpy.OKBLUE}Consolidating using endpoints: {util.Typgpy.OKGREEN}{endpoints}{util.Typgpy.ENDC}")
    print(f"{util.Typgpy.OKBLUE}Total accounts to consolidate: {util.Typgpy.OKGREEN}{len(accounts_info)}{util.Typgpy.ENDC}")
    print(f"{util.Typgpy.OKBLUE}Chain-ID: {util.Typgpy.OKGREEN}{chain_id}{util.Typgpy.ENDC}")
    print(f"{util.Typgpy.OKBLUE}Profile: {util.Typgpy.OKGREEN}{os.environ['HMY_PROFILE']}{util.Typgpy.ENDC}")
    if input("Consolidate accounts?\n[Y]/n > ") != 'Y':
        exit()

    pool = ThreadPool(processes=len(endpoints))
    i, total_amount = 0, 0
    while i < len(endpoints):
        threads = []
        for _ in range(os.cpu_count()):
            threads.append(pool.apply_async(consolidate, (i,)))
            i += 1
            if i >= len(endpoints):
                break
        for t in threads:
            total_amount += t.get()

    exit_code = 0
    print(f"{util.Typgpy.HEADER}Finished sending transactions!{util.Typgpy.ENDC}")
    if args.check:
        print(f"{util.Typgpy.HEADER}Sleeping 90 seconds before checking balances{util.Typgpy.ENDC}")
        time.sleep(90)
        post_bal = 0
        for bal in get_balance_from_node_ip(args.dest_address, endpoints):
            post_bal += bal["amount"]
        if total_amount < post_bal - init_bal:
            print(f"{util.Typgpy.FAIL}{args.dest_address} did not get funded!{util.Typgpy.ENDC}")
            exit_code = 1
        else:
            print(f"{util.Typgpy.HEADER}Successfully consolidated funds!{util.Typgpy.ENDC}")
    print(f"{util.Typgpy.BOLD}Removing imported keys{util.Typgpy.ENDC}")
    for name in added_key_names:
        cli.remove_account(name)
    exit(exit_code)
