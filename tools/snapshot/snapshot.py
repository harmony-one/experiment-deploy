#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
This is the main orchestrator script to execute a snapshot with the given config.

Example Usage:
    ./snapshot.py --config ./mainnet.json

Note that this script was built to be imported as a package from other scripts.
"""
import time
import argparse
import subprocess
import os
import sys
import json
import logging
import traceback
from multiprocessing.pool import ThreadPool

import pexpect
import pyhmy
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


pyhmy_version = '20.5.5'
script_directory = os.path.dirname(os.path.realpath(__file__))
log = logging.getLogger("snapshot")
ips, rsync, ssh_key, condition = [], {}, {}, {}  # Will be populated from config.


def _init_ssh_agent():
    """
    Initialize machine's ssh agent when config is loaded.
    """
    ssh_key['path'] = os.path.expanduser(ssh_key['path'])
    if ssh_key['use_existing_agent']:
        log.debug("using existing ssh agent")
        return
    log.debug(f"adding ssh key {ssh_key['path']} to ssh agent")
    if ssh_key['passphrase'] is None:
        subprocess.check_call(["ssh-add", ssh_key['path']], env=os.environ)
    else:
        proc = pexpect.spawn("ssh-add", [ssh_key['path']], env=os.environ)
        proc.logfile = sys.stdout
        proc.sendline(ssh_key['passphrase'])
        proc.expect(pexpect.EOF)
        log.debug(proc.before.decode())


def _ssh_cmd(user, ip, command):
    """
    Internal SSH command. Assumes ssh agent has been initialized.

    Returns the output of the SSH command.
    Raises subprocess.CalledProcessError if ssh call errored.
    """
    cmd = ["ssh", f"{user}@{ip}"] if ssh_key['use_existing_agent'] else ["ssh", "-i", ssh_key["path"], f"{user}@{ip}"]
    cmd.append(command)
    return subprocess.check_output(cmd, env=os.environ).decode()


def _ssh_script(user, ip, script_path):
    """
    Internal SSH command. Assumes ssh agent has been initialized.

    Returns the output of the SSH command.
    Raises subprocess.CalledProcessError if ssh call errored.
    """
    cmd = ["ssh", f"{user}@{ip}"] if ssh_key['use_existing_agent'] else ["ssh", "-i", ssh_key["path"], f"{user}@{ip}"]
    cmd.append('bash -s')
    with open(script_path, 'rb') as f:
        return subprocess.check_output(cmd, env=os.environ, stdin=f).decode()


def setup_logger():
    logger = logging.getLogger("snapshot")
    file_handler = logging.FileHandler(f"{script_directory}/snapshot.log")
    file_handler.setFormatter(
        logging.Formatter(f"{Typgpy.OKBLUE}(%(threadName)s){Typgpy.OKGREEN}[%(asctime)s]{Typgpy.ENDC} %(message)s"))
    logger.addHandler(file_handler)
    logger.addHandler(logging.StreamHandler(sys.stdout))
    logger.setLevel(logging.DEBUG)
    logger.debug("===== NEW SNAPSHOT =====")


def load_config(config_path):
    """
    Load the given config.

    Raises FileNotFoundError, KeyError, or json.decoder.JSONDecodeError
    """
    with open(config_path, 'r', encoding="utf-8") as f:
        config = json.load(f)
    if {'ips', 'ssh_key', 'rsync', 'condition'} != set(config.keys()):
        raise KeyError(f"config keys: {config.keys()} do not contain 'ips', 'ssh_key', 'condition' or 'rsync'.")
    log.debug(json.dumps(config))
    ips.clear()
    rsync.clear()
    ssh_key.clear()
    condition.clear()
    ips.extend(config['ips'])
    rsync.update(config['rsync'])
    ssh_key.update(config['ssh_key'])
    condition.update(config['condition'])
    _init_ssh_agent()


def sanity_check():
    """
    Checks ALL nodes for config assumptions and liveliness.

    Raises a RuntimeError if the sanity check fails.
    """
    log.debug('starting sanity check')
    if condition['force']:
        log.warning('force snapshot, bypassing sanity check...')
        return

    threads, pool = [], ThreadPool()
    for ip in map(lambda e: e['ip'], ips):
        threads.append(pool.apply_async(is_active_shard, (f"http://{ip}:9500/", condition['last_block_tolerance'])))
    if not all(t.get() for t in threads):
        raise RuntimeError(f"One or more of the configured IPs are either offline "
                           f"or latest block is older than {condition['last_block_tolerance']} seconds")
    log.debug(f"all configured ips are active & synced within tolerance of {condition['last_block_tolerance']} sec")

    threads = []
    for ip_config in ips:
        def fn():  # returning None marks success for this function
            try:
                node_metadata = blockchain.get_node_metadata(f"http://{ip_config['ip']}:9500/", timeout=15)
            except (rpc_exceptions.RPCError, rpc_exceptions.RequestsTimeoutError, rpc_exceptions.RequestsError) as e:
                log.error(traceback.format_exc())
                return f"errored when fetching metadata for {ip_config['ip']}. Error {e}"
            shard, role, network = node_metadata['shard-id'], node_metadata['role'], node_metadata['network']
            if int(shard) != int(ip_config['shard']):
                return f"configured shard {ip_config['shard']} != actual node shard of {shard}. (ip: {ip_config['ip']})"
            if condition['role'] != role:
                return f"configured node role {condition['role']} != actual node role of {role}. (ip: {ip_config['ip']})"
            if condition['network'] != network:
                return f"configured node network {condition['network']} != actual node network of {network}. (ip: {ip_config['ip']})"
            return None  # indicate success
        threads.append(pool.apply_async(fn))
    for t in threads:
        response = t.get()
        if response is not None:
            raise RuntimeError(response)
    log.debug('passed sanity check')


def _setup_rclone(ip_config, script_path):
    """
    Worker to setup rclone on machine.
    """
    log.debug(f"setting up rclone snapshot credentials for {ip_config['ip']}")
    setup_response = _ssh_script(ip_config['user'], ip_config['ip'], script_path)
    log.debug(f"rsync snapshot credentials setup response: {setup_response}")
    verification_cat = _ssh_cmd(ip_config['user'], ip_config['ip'], f"cat {rsync['config_path_on_client']}")
    log.debug(f"rsync snapshot credentials on machine: {ip_config['ip']}: {verification_cat}")


def _cleanup_rclone(ip_config):
    """
    Worker to cleanup rclone on machine.
    """
    log.debug(f"cleaning up rclone snapshot credentials for {ip_config['ip']}")
    cleanup_response = _ssh_cmd(ip_config['user'], ip_config['ip'], f"rm {rsync['config_path_on_client']}")
    log.debug(f"rsync snapshot credentials cleanup response: {cleanup_response}")
    verification_cat = _ssh_cmd(ip_config['user'], ip_config['ip'], f"[ -f {rsync['config_path_on_client']} ] || echo removed file!")
    log.debug(f"rsync snapshot credentials cleanup check: {ip_config['ip']}: {verification_cat}")


def cleanup_rclone():
    """
    Clean/remove rclone credentials that were added (as dictated by the config).

    Note that this will remove the file at whatever the `config_path_on_client`
    specifies in the config.
    """
    threads, pool = [], ThreadPool()
    for ip_config in ips:
        threads.append(pool.apply_async(_cleanup_rclone, (ip_config,)))
    for t in threads:
        t.get()


def setup_rclone():
    """
    Setup rclone credentials on all the snapshot machines.

    Note that this generates a temp bash script to be executed on the snapshot machines.
    """
    threads, pool = [], ThreadPool()
    with open(rsync['config_path_on_host'], 'r') as f:
        rclone_config_raw_string = f.read()
    script_content = f"""#!/bin/bash
echo "{rclone_config_raw_string}" > {rsync['config_path_on_client']}
"""
    script_path = f"/tmp/snapshot_script{hash(time.time())}.sh"
    with open(script_path, 'w') as f:
        f.write(script_content)
    for ip_config in ips:
        threads.append(pool.apply_async(_setup_rclone, (ip_config, script_path)))
    for t in threads:
        t.get()
    os.remove(script_path)


def _parse_args():
    """
    Argument parser that is only used for main execution of this script.
    """
    parser = argparse.ArgumentParser(description='Snapshot script to be ran from command machine')
    default_config_path = f"{script_directory}/config.json"
    parser.add_argument("--config", type=str, default=default_config_path,
                        help=f"path to snapshot config (default {default_config_path})")
    return parser.parse_args()


if __name__ == "__main__":
    assert pyhmy.__version__.public() == pyhmy_version, f'install correct pyhmy version with `python3 -m pip install pyhmy=={pyhmy_version}`'
    setup_logger()
    try:
        load_config(_parse_args().config)
        log.debug("initialized snapshot script")
        sanity_check()
        setup_rclone()
        # TODO: Copy over logic from old script & test snapshot
        cleanup_rclone()
    except Exception as e:
        log.fatal(traceback.format_exc())
        log.fatal(f'script crashed with error {e}')
        exit(1)
    log.debug('finished snapshot successfully')
