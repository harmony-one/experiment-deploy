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

import argparse
import logging
import sys
import time
from multiprocessing.pool import ThreadPool

import pyhmy
from pyhmy import (
    blockchain,
    rpc,
    Typgpy
)


pyhmy_version = '20.5.3'


def parse_args():
    parser = argparse.ArgumentParser(description='Recover snapshot script to be ran from devops machine')
    parser.add_argument("log_dir", type=str, help="Path to the log directory that contains the networks's shard?.txt files.")
    parser.add_argument("--network", type=str, default="mainnet", help="Network type (default: mainnet)")
    parser.add_argument("--shard", type=str, default="0,1,2,3",
                        help="String in CSV format of shards to recover, default is '0,1,2,3'")
    return parser.parse_args()


def setup_logger():
    logger = logging.getLogger("snapshot")
    file_handler = logging.FileHandler(f"{args.log_dir}/recover_from_snapshot.log")
    file_handler.setFormatter(logging.Formatter(f"{Typgpy.OKGREEN}[%(asctime)s]{Typgpy.ENDC} %(message)s"))
    logger.addHandler(file_handler)
    logger.addHandler(logging.StreamHandler(sys.stdout))
    logger.setLevel(logging.DEBUG)
    print(f"Log file saved to: {args.log_dir}/recover_from_snapshot.log")
    return logger


def process_args():
    return {}, args.network


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


def reset_dbs_interactively():
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


def restart_and_check():
    """
    Main restart and verification function after DBs have been restored.
    """
    threads = []
    post_check_pool = ThreadPool()
    for shard in ips_for_shard.keys():
        log.debug(f"starting restart for shard {shard}; ips: {ips_for_shard[shard]}")
        threads.append(post_check_pool.apply_async(restart_all, (ips_for_shard[shard],)))
    for t in threads:
        t.get()
    log.debug(f"finished restarting shards {sorted(ips_for_shard.keys())}")

    sleep_b4_running_check = 10
    log.debug(f"sleeping {sleep_b4_running_check} seconds before checking if all nodes started")
    time.sleep(sleep_b4_running_check)

    threads = []
    for shard in ips_for_shard.keys():
        log.debug(f"starting node restart verification for shard {shard}; ips: {ips_for_shard[shard]}")
        threads.append(post_check_pool.apply_async(verify_all_started, (ips_for_shard[shard],)))
    if not all(t.get() for t in threads):
        raise SystemExit(f"not all nodes restarted, check logs for details: "
                         f"{args.log_dir}/recover_from_snapshot.log")

    sleep_b4_progress_check = 30
    log.debug(f"sleeping {sleep_b4_progress_check} seconds before checking if all nodes are making progress")
    time.sleep(sleep_b4_progress_check)

    threads = []
    for shard in ips_for_shard.keys():
        log.debug(f"starting node progress verification for shard {shard}; ips: {ips_for_shard[shard]}")
        threads.append(post_check_pool.apply_async(verify_all_progressed, (ips_for_shard[shard],)))
    if not all(t.get() for t in threads):
        raise SystemExit(f"not all nodes made progress, check logs for details: "
                         f"{args.log_dir}/recover_from_snapshot.log")
    log.debug("recovery succeeded!")


if __name__ == "__name__":
    assert pyhmy.__version__.public() == pyhmy_version, f'install correct pyhmy version with `python3 -m pip install pyhmy=={pyhmy_version}`'
    log, args = setup_logger(), parse_args()
    ips_for_shard, network = process_args()
    reset_dbs_interactively()
    if input(f"Restart shards {sorted(ips_for_shard.keys())}? [Y/n]\n> ").lower() in {'yes', 'y'}:
        restart_and_check()
    log.debug("finished recovery")
