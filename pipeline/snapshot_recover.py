#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Recover a network using a given snapshot.

Note that this script has assumptions regarding its path and relies
on the rest of the repository being cloned. Here are the assumptions:
* node_ssh.sh needs to be in the current working directory and never requires interaction.
* $(pwd)/../tools/snapshot/rclone.conf contains the default rclone config for
  a node to download the snapshot db.
* $(pwd)/utils/scripting.py is a python3 library

Note that this script assumes that the given bin is accessible from the machine it is running on.

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

from .utils.scripting import (
    interact,
    aws_s3_ls,
    setup_logger,
    input_prefill,
    ipv4_regex
)

script_directory = os.path.dirname(os.path.realpath(__file__))
log = logging.getLogger("snapshot_recovery")
supported_networks = {"mainnet", "testnet", "staking", "partner", "stress"}
beacon_chain_shard = 0


def _ssh_cmd(ip, command):
    """
    Internal SSH command.
    Assumes node_ssh.sh is executable and is in the current directory.

    Returns the output of the SSH command.
    Raises subprocess.CalledProcessError if ssh call errored.
    """
    node_ssh_dir = f"{script_directory}/node_ssh.sh"
    cmd = [node_ssh_dir, ip, command]
    return subprocess.check_output(cmd, env=os.environ).decode()


def _ssh_script(ip, bash_script_path):
    """
    Internal SSH command.
    Assumes node_ssh.sh is executable and is in the current directory.

    Returns the output of the SSH command.
    Raises subprocess.CalledProcessError if ssh call errored.
    """
    node_ssh_dir = f"{script_directory}/node_ssh.sh"
    cmd = [node_ssh_dir, ip, 'bash -s']
    with open(bash_script_path, 'rb') as f:
        return subprocess.check_output(cmd, env=os.environ, stdin=f).decode()


def verify_network(network, ips_per_shard):
    """
    Verify that nodes are for the given network. Requires interaction if failure.

    If nodes are offline, prompt to ignore or reboot nodes and try again.

    Assumes `ips_per_shard` has valid IPs.
    """

    def verify(ips):
        thread_and_ip_list, pool = [], ThreadPool(processes=200)  # single simple RPC request, pool can be large
        for ip in ips:
            el = (pool.apply_async(check_node, (ip,)), ip)
            thread_and_ip_list.append(el)

        results = []
        for thread, ip in thread_and_ip_list:
            results.append((thread.get(), ip))
        return results  # List of tuples where first element of tuple indicates error cause if not None

    def check_node(ip):  # returning None marks success for this function
        try:
            node_metadata = blockchain.get_node_metadata(f"http://{ip}:9500/", timeout=10)
            sharding_structure = blockchain.get_sharding_structure(f"http://{ip}:9500/", timeout=15)
        except (rpc_exceptions.RPCError, rpc_exceptions.RequestsTimeoutError, rpc_exceptions.RequestsError) as e:
            log.error(traceback.format_exc())
            return f"error on RPC from {ip}. Error {e}"
        if node_metadata['network'] != network:
            return f"node {ip} has network {node_metadata['network']} != {network}"
        if len(sharding_structure) >= max(ips_per_shard.keys()):
            return f"node {ip} has sharding structure that is smaller than max shard-id of {max(ips_per_shard.keys())}"
        return None  # indicate success

    all_ips = []
    for lst in ips_per_shard.values():
        all_ips.extend(lst)

    while True:
        # Verify nodes
        results = verify(all_ips)
        failed_checks = [el for el in results if el[0] is not None]
        if not failed_checks:
            return

        # Prompt user on next course of action
        print(f"{Typgpy.FAIL}Some nodes failed node verification checks!{Typgpy.ENDC}")
        failed_ips = []
        for reason, ip in failed_checks:
            print(f"{Typgpy.OKGREEN}{ip}{Typgpy.ENDC} failed because of: {reason}")
            failed_ips.append(ip)
        choices = [
            "Reboot nodes and try again",
            "Ignore"
        ]
        response = interact("", choices)

        # Execute next course of action
        if response == choices[-1]:  # Ignore
            return
        if response == [0]:  # Reboot nodes and try again
            restart_all(failed_ips)
            log.debug("sleeping 10 seconds before checking all nodes again...")
            time.sleep(10)
            continue


def current_stats(ips_per_shard):
    """
    Report the current stats of the network.

    Per shard, report:
        * All unique block heights
        * Min block height
        * Max block height
        * Offline nodes
        * Nodes that have not made progress in the last 150 seconds

    Assumes `ips_per_shard` has been verified.
    """
    # TODO: implement


def backup_existing_dbs(ips, shard):
    """
    Simply tar the existing db (locally) if needed in the future
    """
    pass


def setup_rclone(ips, rclone_config_path):
    """
    Setup rclone with the config at the given `rclone_config_path`.
    Assumes `rclone_config_path` is a rclone config file.
    """
    pass


def rsync_recovered_dbs(ips, shard, snapshot_bin):
    """
    Assumption is that nodes have rclone setup with appropriate credentials.
    Assumes the `snapshot_bin` matches rclone config setup on machine
    and follow format: <rclone-config>:<bin>.
    """
    pass


def reset_dbs_interactively(ips_per_shard, snapshots_per_shard, rclone_config_path):
    """
    Bulk of the work is handled here.
    Actions done interactively to ensure security.

    Assumes `ips_per_shard` has been verified.
    Assumes `snapshots_per_shard` has beacon-chain snapshot path.
    Assumes `rclone_config_path` is a rclone config file.
    and follow format: <rclone-config>:<bin>.
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

    Assumes `ips_per_shard` has been verified.
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
        raise RuntimeError(f"not all nodes restarted, check logs for details")

    sleep_b4_progress_check = 60
    log.debug(f"sleeping {sleep_b4_progress_check} seconds before checking if all nodes are making progress")
    time.sleep(sleep_b4_progress_check)

    threads = []
    for shard in ips_per_shard.keys():
        log.debug(f"starting node progress verification for shard {shard}; ips: {ips_per_shard[shard]}")
        threads.append(post_check_pool.apply_async(verify_all_progressed, (ips_per_shard[shard],)))
    if not all(t.get() for t in threads):
        raise RuntimeError(f"not all nodes restarted, check logs for details")
    log.debug("recovery succeeded!")


def _get_ips_per_shard_from_file(file_path, shard):
    """
    Internal function to get IPs per shard from a given file interactively.

    Assumes that `file_path` exists, that its basename follows ^shard[0-9]+.txt,
    and that the file contains IPs in new line separated format.

    Returns a list of chosen IPs or None if shard is to be ignored.
    """
    # Load file & verify shard has not loaded IPs
    file = os.path.basename(file_path)
    file_shard = int(file.replace("shard", "").replace(".txt", ""))
    assert file_shard == shard, f"file shard ({file_shard}) for {file_path} != {shard}"
    with open(file_path, 'r', encoding='utf-8') as f:
        ips = [line.strip() for line in f.readlines() if re.search(ipv4_regex, line)]
    if not ips:
        raise RuntimeError(f"no VALID IP was loaded from file: '{file_path}'")
    log.debug(f"Candidate IPs for shard {shard}: {ips}")

    # Prompt user with actions to do on read IPs
    print(f"\nShard {Typgpy.HEADER}{shard}{Typgpy.ENDC} ips ({len(ips)}):")
    for i, ip in enumerate(ips):
        print(f"{i + 1}.\t{Typgpy.OKGREEN}{ip}{Typgpy.ENDC}")
    choices = [
        "Add all above IPs",
        "Choose IPs from above to add (interactively)",
        "Ignore"
    ]
    response = interact("", choices)

    # Execute action on read IPs
    if response == choices[-1]:  # Ignore
        log.debug(f"ignoring IPs from shard {shard}")
        return None
    if response == choices[0]:  # Add all above IPs
        log.debug(f"shard {shard} IPs: {ips}")
        return ips
    if response == choices[1]:  # Choose IPs from above to add (interactively)
        chosen_ips = []
        for ip in ips:
            prompt = f"Add {Typgpy.OKGREEN}{ip}{Typgpy.ENDC} for shard {Typgpy.HEADER}{shard}{Typgpy.ENDC}?"
            if interact(prompt, ["yes", "no"]) == "yes":
                chosen_ips.append(ip)
        if not chosen_ips:
            msg = f"chose 0 IPs for shard {shard}, ignoring shard"
            log.debug(msg)
            return None
        print(f"\nShard {Typgpy.HEADER}{shard}{Typgpy.ENDC} "
              f"{Typgpy.UNDERLINE}chosen{Typgpy.ENDC} ips ({len(chosen_ips)})")
        for i, ip in enumerate(chosen_ips):
            print(f"{i + 1}.\t{Typgpy.OKGREEN}{ip}{Typgpy.ENDC}")
        if interact(f"Add above ips for shard {Typgpy.HEADER}{shard}{Typgpy.ENDC}?", ["yes", "no"]) == "yes":
            log.debug(f"shard {shard} IPs: {chosen_ips}")
            return chosen_ips
        log.debug(f"ignoring IPs from shard {shard}")
        return None


def get_ips_per_shard(logs_dir):
    """
    Setup function to get the IPs per shard given the `logs_dir`.
    """
    log.debug("Loading IPs from given directory...")
    ips_per_shard = {}
    input_choices = [
        "Read IPs from log directory and choose interactively",
        "Provide IPs interactively as a CSV string for each shard"
    ]
    response = interact("How would you like to input network IPs?", input_choices)
    if response == input_choices[0]:  # Read IPs from log directory and choose interactively
        log.debug("Reading IPs from file")
        for file in os.listdir(logs_dir):
            if not re.match(r"shard[0-9]+.txt", file):
                continue
            shard = int(file.replace("shard", "").replace(".txt", ""))
            if shard in ips_per_shard.keys():
                raise RuntimeError(f"Multiple IP files for shard {shard}")
            shard_ips = _get_ips_per_shard_from_file(f"{logs_dir}/{file}", shard)
            if shard_ips is not None:
                ips_per_shard[shard] = shard_ips
    elif response == input_choices[1]:  # Provide IPs interactively as a CSV string for each shard
        log.debug("Reading IPs from console interactively")
        shard = 0
        while True:
            choices = ["yes", "skip", "finish"]
            action = interact(f"Enter IPs for shard {shard}?", choices)
            if action == choices[-1]:  # finished
                break
            if action == choices[1]:  # skip
                shard += 1
                continue
            if action == choices[0]:  # yes
                ips_as_csv = input(f"Enter IPs as a CSV string for shard {shard}\n> ")
                log.debug(f"raw csv input for shard {shard}: {ips_as_csv}")
                shard_ips = []
                for ip in map(lambda e: e.strip(), ips_as_csv.split(",")):
                    if not re.search(ipv4_regex, ip):
                        log.debug(f"throwing away '{ip}' as it is not a valid ipv4 address")
                    else:
                        shard_ips.append(ip)
                if shard_ips:
                    print(f"\nShard {Typgpy.HEADER}{shard}{Typgpy.ENDC} "
                          f"{Typgpy.UNDERLINE}given & filtered{Typgpy.ENDC} ips ({len(shard_ips)})")
                    for i, ip in enumerate(shard_ips):
                        print(f"{i + 1}.\t{Typgpy.OKGREEN}{ip}{Typgpy.ENDC}")
                    if interact(f"Add above ips for shard {Typgpy.HEADER}{shard}{Typgpy.ENDC}?", ["yes", "no"]) == "yes":
                        log.debug(f"shard {shard} IPs: {shard_ips}")
                        ips_per_shard[shard] = shard_ips
                else:
                    log.debug(f"no valid ips to add to shard {shard}")
                shard += 1
                continue

    # Final print loaded IPs
    for shard in sorted(ips_per_shard.keys()):
        print(f"Shard {Typgpy.HEADER}{shard}{Typgpy.ENDC} {Typgpy.UNDERLINE}loaded{Typgpy.ENDC} IPs:")
        print('-' * 16)
        for ip in sorted(ips_per_shard[shard]):
            print(ip)
        print()

    final_report = "Added "
    for k, v in ips_per_shard.items():
        final_report += f"{len(v)} ips for shard {k}; "
    log.debug(final_report[:-2])
    return ips_per_shard


def select_snapshot_for_shard(network, snapshot_bin, shard):
    """
    Interactively select the snapshot to ensure security.

    Assumes the `snapshot_bin` follow format: <rclone-config>:<bin>.
    Assumes that AWS CLI is setup on machine that is running this script.
    Assumes AWS s3 structure is:
        <bin>/<network>/<db-type>/<shard-id>/harmony_db_<shard-id>.<date>.<block_height>/

    Returns string of db snapshot, return None if no db could be selected.
    """

    def filter_db(entry):
        try:
            return int(entry.split('.')[-1])
        except (ValueError, KeyError):
            return -1

    # Get to desired bucket of snapshot DBs
    snapshot_bin = f"{snapshot_bin.split(':')[1]}/{network}/"
    db_types = aws_s3_ls(snapshot_bin)
    if not db_types:
        return None
    selected_db_type = interact("Select recovery DB type", db_types)
    log.debug(f"selected {selected_db_type} db type")
    snapshot_bin += f"{selected_db_type}/"
    shards = [int(s) for s in aws_s3_ls(snapshot_bin)]
    if shard not in shards:
        raise RuntimeError(f"snapshot db not found for shard {shard}")
    snapshot_bin += f"{shard}/"
    dbs = sorted(filter(lambda e: filter_db(e) >= 0, aws_s3_ls(snapshot_bin)), key=filter_db, reverse=True)
    if not dbs:
        return None

    # Request db
    presented_dbs_count = 10
    while True:
        prompt_db = dbs.copy()[:presented_dbs_count] + ["Look for more DBs"]
        prompt = f"Select DB for shard {shard}. Format: harmony_db_SHARD.Y-M-D-H-M-S.BLOCK)"
        response = interact(prompt, prompt_db, sort=False)
        if response == prompt_db[-1]:
            presented_dbs_count *= 2
            continue
        else:
            db = f"{snapshot_bin}/{response}"
            log.debug(f"chose DB: {db} for shard {shard}")
            return db


def get_snapshot_per_shard(network, ips_per_shard, snapshot_bin):
    """
    Setup function to get the snapshot DB path (used by rclone) for each shard.

    Assumes the `snapshot_bin` follow format: <rclone-config>:<bin>.
    Assumes that AWS CLI is setup on machine that is running this script.
    """
    snapshot_per_shard = {}
    shards, actual_snapshot_bin = ips_per_shard.keys(), f"{snapshot_bin.split(':')[1]}/{network}/"
    if beacon_chain_shard not in shards:
        shards.append(beacon_chain_shard)

    for shard in sorted(shards, reverse=True):
        choices = [
            "Interactively select snapshot db, starting from latest",
            "Manually specify path (and optionally bin) for snapshot db"
        ]
        response = interact(f"How to get snapshot db for shard {shard}?", choices)

        if response == choices[0]:  # Interactively select snapshot db, starting from latest
            snapshot = select_snapshot_for_shard(network, snapshot_bin, shard)
            if snapshot is None:
                raise RuntimeError(f"Could not find snapshot for shard {shard}! "
                                   f"Check specified snapshot bin or ignore shard when loading IPs.")
            snapshot_per_shard[shard] = snapshot
            continue
        if response == choices[1]:  # Manually specify path (and optionally bin) for snapshot db
            snapshot = input_prefill(f"Enter snapshot path (for rclone) on shard {shard}\n> ",
                                     prefill=f"{actual_snapshot_bin}/")
            log.debug(f"chose DB: {snapshot} for shard {shard}")
            try:
                assert len(aws_s3_ls(snapshot)) > 0, f"given snapshot bin '{snapshot}' is empty"
            except subprocess.CalledProcessError as e:
                error_msg = f"Machine is unable to list s3 files at '{snapshot}'. Error: {e}"
                print(error_msg)
                log.error(traceback.format_exc())
                log.error(error_msg)
                if interact(f"Ignore error?", ["yes", "no"]) == "no":
                    raise RuntimeError(error_msg) from e
            snapshot_per_shard[shard] = snapshot
            continue

    assert len(snapshot_per_shard.keys()) == len(ips_per_shard.keys()), "sanity check for ips/snapshot per shard failed"
    return snapshot_per_shard


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
    parser = argparse.ArgumentParser(description='Snapshot recovery script.')
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
        setup_logger(f"{script_directory}/logs/{os.environ['HMY_PROFILE']}/snapshot_recovery.log",
                     "snapshot_recovery", do_print=True, verbose=True)
    ips_per_shard = get_ips_per_shard(args)
    verify_network(args.network, ips_per_shard)
    snapshots_per_shard = get_snapshot_per_shard(args.network, ips_per_shard, args.snapshot_bin)
    reset_dbs_interactively(ips_per_shard, snapshots_per_shard, args.rclone_config_path)
    # restart_and_check(ips_per_shard)
    log.debug("finished recovery")
