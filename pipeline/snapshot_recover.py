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
log = logging.getLogger("snapshot")
beacon_chain_shard = 0


def parse_args():
    parser = argparse.ArgumentParser(description='Recover snapshot script to be ran from devops machine')
    parser.add_argument("log_dir", type=str, help="Path to the log directory that contains the networks's shard?.txt files.")
    parser.add_argument("--network", type=str, default="mainnet", help="Network type (default: mainnet)")
    parser.add_argument("--shard", type=str, default="0,1,2,3",
                        help="String in CSV format of shards to recover, default is '0,1,2,3'")
    return parser.parse_args()


def setup_logger(do_print=True):
    """
    Setup the logger for the snapshot package and returns the logger.
    """
    logger = logging.getLogger("snapshot")
    file_handler = logging.FileHandler(f"{script_directory}/snapshot.log")
    file_handler.setFormatter(
        logging.Formatter(f"(%(threadName)s)[%(asctime)s] %(message)s"))
    logger.addHandler(file_handler)
    if do_print:
        logger.addHandler(logging.StreamHandler(sys.stdout))
    logger.setLevel(logging.DEBUG)
    logger.debug("===== NEW SNAPSHOT =====")
    return logger


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
    if input(f"Restart shards {sorted(ips_per_shard.keys())}? [Y/n]\n> ").lower() not in {'yes', 'y'}:
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
    Internal function to get the IPs per shard given a parsed args.
    """
    return {}


def _parse_args():
    """
    Argument parser that is only used for main execution of this script.
    """
    parser = argparse.ArgumentParser(description='Snapshot script to be ran from command machine')
    default_config_path = f"{script_directory}/config.json"
    parser.add_argument("--config", type=str, default=default_config_path,
                        help=f"path to snapshot config (default {default_config_path})")
    parser.add_argument("--bucket-sync", action='store_true',
                        help="Enable syncing to external bucket (where bucket is defined in the config)")
    args = parser.parse_args()
    return _get_ips_per_shard(args), args


if __name__ == "__name__":
    assert pyhmy.__version__.major == 20
    assert pyhmy.__version__.minor >= 5
    assert pyhmy.__version__.micro >= 5
    ips_per_shard, args = _parse_args()
    setup_logger()
    reset_dbs_interactively(ips_per_shard)
    restart_and_check(ips_per_shard)
    log.debug("finished recovery")
