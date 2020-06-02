#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Recover a network using a given snapshot.

Note that this script has assumptions regarding its path and relies
on the rest of the repository being cloned. Here are the assumptions:
* node_ssh.sh needs to be in the current working directory and never requires interaction.
* $(pwd)/../tools/snapshot/rclone.conf contains the default rclone config for
  a node to download the snapshot db.

Note that explorer nodes are recovered with a non-archival db.
Manual archival recovery will need to be afterwards.

Example Usage:
    TODO: example
"""

import time
import datetime
import argparse
import subprocess
import os
import sys
import json
import logging
import traceback
import re
from multiprocessing.pool import ThreadPool

import pexpect
import dns.resolver
import requests
import pyhmy
from pagerduty_api import Alert
from pyhmy.rpc import (
    exceptions as rpc_exceptions
)
from pyhmy.util import (
    is_active_shard,
    Typgpy
)
from pyhmy import (
    blockchain,
)

script_directory = os.path.dirname(os.path.realpath(__file__))
log = logging.getLogger("snapshot_recovery")
supported_networks = {"mainnet", "testnet", "staking", "partner", "stress"}
beacon_chain_shard = 0

_ip_regex = r"^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"


def setup_logger(do_print=True):
    """
    Setup the logger for the snapshot package and returns the logger.
    """
    log_file = f"{script_directory}/logs/{os.environ['HMY_PROFILE']}/snapshot_recovery.log"
    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    logger = logging.getLogger("snapshot_recovery")
    file_handler = logging.FileHandler(log_file)
    file_handler.setFormatter(
        logging.Formatter(f"(%(threadName)s)[%(asctime)s] %(message)s"))
    logger.addHandler(file_handler)
    if do_print:
        logger.addHandler(logging.StreamHandler(sys.stdout))
    logger.setLevel(logging.DEBUG)
    logger.debug("===== NEW RECOVERY =====")
    print(f"Logs saved to: {log_file}")
    return logger


def interact(prompt, selection_list):
    """
    The single source of interaction with the console.
    All interaction must confine to this function's requirement.

    Prompt the user with `prompt` and an enumerated selection from a sorted `selection_list`.
    Take in an integer, n, such that 0 <= n < len(`selection_list`).
    If a `log` is provided, log the interaction and all errors at the info and error level respectively.

    Keeps prompting user for input if input is invalid.
    Prints user interaction before returning.

    Note that all new lines from `prompt` and `selection_list` will be removed.

    Returns n and corresponding selection string from `selection_list`.
    """
    input_prompt = f"{Typgpy.BOLD}Select option (number):{Typgpy.ENDC}\n> "
    prompt, selection_list = prompt.replace("\n", ""), sorted(map(lambda e: e.replace("\n", ""), selection_list))
    prompt_new_line_count = sum(1 for el in selection_list if el) + 3  # 1 for given prompt, 2 for input prompt
    if prompt:
        prompt_new_line_count += 1
    printed_new_line_count = 0
    print()

    while True:
        if prompt:
            print(prompt)
        for i, selection in enumerate(selection_list):
            print(f"{Typgpy.BOLD}[{i}]{Typgpy.ENDC}\t{selection}")
        user_input = input(input_prompt)
        printed_new_line_count += prompt_new_line_count
        try:
            n = int(user_input)
            if n >= len(selection_list):
                continue
            selection_report = f"{prompt} {Typgpy.BOLD}[{n}]{Typgpy.ENDC} {selection_list[n]}".strip()
            for i in range(printed_new_line_count):
                sys.stdout.write("\033[K")
                if i + 1 < printed_new_line_count:
                    sys.stdout.write("\033[F")
            print(selection_report)
            return selection_list[n]
        except ValueError:
            pass


def select_snapshot():
    """
    Interactively select the snapshot to ensure security
    """
    pass


def backup_existing_dbs(ips, shard):
    """
    Simply tar the existing db if needed in the future
    """
    pass


def rsync_recovered_dbs(ips, shard):
    """
    Assumption is that nodes have rclone setup with appropriate credentials.
    """
    pass


def reset_dbs_interactively(ips_per_shard):
    """
    Bulk of the work is handled here.
    Actions done interactively to ensure security.
    Done it batches with confirmation for security.
    """
    pass


def restart_all(ips):
    """
    Send restart command to all nodes asynchronously.
    """
    pass


def verify_all_started(ips):
    """
    Verify all nodes started asynchronously.
    """
    pass


def verify_all_progressed(ips):
    """
    Verify all nodes progressed asynchronously.
    """
    pass


def restart_and_check(ips_per_shard):
    """
    Main restart and verification function after DBs have been restored.
    """
    if interact(f"Restart shards: {sorted(ips_per_shard.keys())}?", ["yes", "no"]) == "no":
        return

    threads = []
    post_check_pool = ThreadPool()
    for shard in ips_per_shard.keys():
        log.debug(f"starting restart for shard {shard}; ips: {ips_per_shard[shard]}")
        threads.append(post_check_pool.apply_async(restart_all, (ips_per_shard[shard],)))
    for t in threads:
        t.get()
    log.debug(f"finished restarting shards {sorted(ips_per_shard.keys())}")

    sleep_b4_running_check = 10
    log.debug(f"sleeping {sleep_b4_running_check} seconds before checking if all nodes started")
    time.sleep(sleep_b4_running_check)

    threads = []
    for shard in ips_per_shard.keys():
        log.debug(f"starting node restart verification for shard {shard}; ips: {ips_per_shard[shard]}")
        threads.append(post_check_pool.apply_async(verify_all_started, (ips_per_shard[shard],)))
    if not all(t.get() for t in threads):
        raise SystemExit(f"not all nodes restarted, check logs for details: "
                         f"{args.log_dir}/recover_from_snapshot.log")

    sleep_b4_progress_check = 60
    log.debug(f"sleeping {sleep_b4_progress_check} seconds before checking if all nodes are making progress")
    time.sleep(sleep_b4_progress_check)

    threads = []
    for shard in ips_per_shard.keys():
        log.debug(f"starting node progress verification for shard {shard}; ips: {ips_per_shard[shard]}")
        threads.append(post_check_pool.apply_async(verify_all_progressed, (ips_per_shard[shard],)))
    if not all(t.get() for t in threads):
        raise SystemExit(f"not all nodes made progress, check logs for details: "
                         f"{args.log_dir}/recover_from_snapshot.log")
    log.debug("recovery succeeded!")


def _get_ips_per_shard(args):
    """
    Internal function to get the IPs per shard given a parsed args, only used for main execution.
    """
    log.debug("Loading IPs from given directory...")

    ips_per_shard = {}
    for file in os.listdir(args.logs_dir):
        if re.match(r"shard[0-9]+.txt", file):
            shard = int(file.replace("shard", "").replace(".txt", ""))
            if shard in ips_per_shard.keys():
                raise RuntimeError(f"Multiple IP files for shard {shard}")
            with open(f"{args.logs_dir}/{file}", 'r', encoding='utf-8') as f:
                ips = [line.strip() for line in f.readlines() if re.search(_ip_regex, line)]
            if not ips:
                raise RuntimeError(f"no VALID IP was loaded from file: '{args.logs_dir}/{file}'")
            log.debug(f"Candidate IPs for shard {shard}: {ips}")

            print(f"\nShard {Typgpy.HEADER}{shard}{Typgpy.ENDC} ips ({len(ips)}):")
            for i, ip in enumerate(ips):
                print(f"{i + 1}.\t{Typgpy.OKGREEN}{ip}{Typgpy.ENDC}")
            choices = [
                "Add all IPs",
                "Select IPs to add (interactively)",
                "Ignore"
            ]
            response = interact("", choices)

            if response == choices[-1]:
                log.debug(f"ignoring IPs from shard {shard}")
                continue
            if response == choices[0]:
                log.debug(f"shard {shard} IPs: {ips}")
                ips_per_shard[shard] = ips
                continue
            if response == choices[1]:
                selected_ips = []
                for ip in ips:
                    prompt = f"Add {Typgpy.OKGREEN}{ip}{Typgpy.ENDC} for shard {Typgpy.HEADER}{shard}{Typgpy.ENDC}?"
                    if interact(prompt, ["yes", "no"]) == "yes":
                        selected_ips.append(ip)
                if not selected_ips:
                    msg = f"selected 0 IPs for shard {shard}, ignoring shard"
                    log.debug(msg)
                    continue
                print(f"\nShard {Typgpy.HEADER}{shard}{Typgpy.ENDC} "
                      f"{Typgpy.UNDERLINE}selected{Typgpy.ENDC} ips ({len(selected_ips)})")
                for i, ip in enumerate(selected_ips):
                    print(f"{i + 1}.\t{Typgpy.OKGREEN}{ip}{Typgpy.ENDC}")
                if interact(f"Add ips for shard {Typgpy.HEADER}{shard}{Typgpy.ENDC}?", ["yes", "no"]) == "yes":
                    log.debug(f"shard {shard} IPs: {selected_ips}")
                    ips_per_shard[shard] = selected_ips
                else:
                    log.debug(f"ignoring IPs from shard {shard}")
                continue

    for shard in sorted(ips_per_shard.keys()):
        print(f"Shard {Typgpy.HEADER}{shard}{Typgpy.ENDC} {Typgpy.UNDERLINE}loaded{Typgpy.ENDC} IPs:")
        print('-' * 16)
        for ip in sorted(ips_per_shard[shard]):
            print(ip)
        print()

    final_report = "Added "
    for k, v in ips_per_shard.items():
        final_report += f"{len(v)} ips for shard {k}; "
    log.debug(final_report)
    return ips_per_shard


def _assumption_check(args):
    """
    Internal function that checks the assumptions of the script, only used for main execution.
    """
    assert args.network in supported_networks, f"given network must be one of {supported_networks}"
    assert os.path.isfile(f"{script_directory}/node_ssh.sh"), "script not in pipeline directory"
    assert os.path.isdir(args.logs_dir), "given logs directory is not a directory"
    if not any(f for f in os.listdir(args.logs_dir) if re.match(r"shard[0-9]+.txt", f)):
        raise AssertionError(f"expected given logs directory, {args.logs_dir} to contain a shard?.txt file")
    assert os.path.isfile(args.rclone_config_path), "given rclone config file path is not a file"
    assert re.match(r".*:.*", args.snapshot_bin), "given snapshot bin does not follow format: <rclone-config>:<bin>"


def _parse_args():
    """
    Argument parser that is only used for main execution.
    """
    if 'HMY_PROFILE' not in os.environ:
        raise SystemExit("HMY_PROFILE not set, exiting...")
    parser = argparse.ArgumentParser(description='Snapshot recovery script')
    parser.add_argument("network", type=str, help=f"{supported_networks}")
    default_log_dir = f"{script_directory}/logs/{os.environ['HMY_PROFILE']}"
    parser.add_argument("--logs-dir", type=str,
                        help="the logs directory containing the shard?.txt files needed to ssh into the machines, "
                             f"default is '{default_log_dir}'")
    default_rclone_config_path = f"{script_directory}/../tools/snapshot/rclone.conf"
    parser.add_argument("--rclone-config-path", type=str, default=default_rclone_config_path,
                        help="path to rclone config to download the snapshot db, "
                             f"default is '{default_rclone_config_path}'")
    parser.add_argument("--snapshot-bin", type=str, default=f"snapshot:harmony-snapshot",
                        help="the rclone config name (based on `--rclone-config`) and bin to download the snapshot db, "
                             "default is 'snapshot:harmony-snapshot'")
    parser.add_argument("--verbose", action="store_true")
    return parser.parse_args()


if __name__ == "__main__":
    assert pyhmy.__version__.major == 20
    assert pyhmy.__version__.minor >= 5
    assert pyhmy.__version__.micro >= 5
    args = _parse_args()
    _assumption_check(args)
    if args.verbose:
        setup_logger(do_print=True)
    ips_per_shard = _get_ips_per_shard(args)
    reset_dbs_interactively(ips_per_shard)
    restart_and_check(ips_per_shard)
    log.debug("finished recovery")
