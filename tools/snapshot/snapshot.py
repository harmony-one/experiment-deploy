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
beacon_chain_shard = 0
machines, rsync, ssh_key, condition = [], {}, {}, {}  # Will be populated from config.


def setup_logger():
    """
    Setup the logger for the snapshot package and returns the logger.
    """
    logger = logging.getLogger("snapshot")
    file_handler = logging.FileHandler(f"{script_directory}/snapshot.log")
    file_handler.setFormatter(
        logging.Formatter(f"{Typgpy.OKBLUE}(%(threadName)s){Typgpy.OKGREEN}[%(asctime)s]{Typgpy.ENDC} %(message)s"))
    logger.addHandler(file_handler)
    logger.addHandler(logging.StreamHandler(sys.stdout))
    logger.setLevel(logging.DEBUG)
    logger.debug("===== NEW SNAPSHOT =====")
    return logger


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


def _ssh_script(user, ip, bash_script_path):
    """
    Internal SSH command. Assumes ssh agent has been initialized.

    Returns the output of the SSH command.
    Raises subprocess.CalledProcessError if ssh call errored.
    """
    cmd = ["ssh", f"{user}@{ip}"] if ssh_key['use_existing_agent'] else ["ssh", "-i", ssh_key["path"], f"{user}@{ip}"]
    cmd.append('bash -s')
    with open(bash_script_path, 'rb') as f:
        return subprocess.check_output(cmd, env=os.environ, stdin=f).decode()


def load_config(config_path):
    """
    Load the given config.

    Raises FileNotFoundError, KeyError, or json.decoder.JSONDecodeError
    """
    with open(config_path, 'r', encoding="utf-8") as f:
        config = json.load(f)
    if {'machines', 'ssh_key', 'rsync', 'condition'} != set(config.keys()):
        raise KeyError(f"config keys: {config.keys()} do not contain 'machines', 'ssh_key', 'condition' or 'rsync'.")
    log.debug(json.dumps(config))
    machines.clear()
    rsync.clear()
    ssh_key.clear()
    condition.clear()
    machines.extend(config['machines'])
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

    config_shard_set = set(map(lambda e: e['shard'], machines))
    if len(config_shard_set) != len(machines):
        raise RuntimeError(f"Number of unique shards does not equal number of configured machines. "
                           f"Snapshot only supports 1 machines per shard.")
    if beacon_chain_shard not in config_shard_set:
        raise RuntimeError(f"config does not specify beacon chain ({beacon_chain_shard})")

    threads, pool = [], ThreadPool()
    for machine in machines:
        def fn():  # returning None marks success for this function
            try:
                node_metadata = blockchain.get_node_metadata(f"http://{machine['ip']}:9500/", timeout=15)
            except (rpc_exceptions.RPCError, rpc_exceptions.RequestsTimeoutError, rpc_exceptions.RequestsError) as e:
                log.error(traceback.format_exc())
                return f"errored when fetching metadata for {machine['ip']}. Error {e}"
            shard, role, network = node_metadata['shard-id'], node_metadata['role'], node_metadata['network']
            is_leader, is_archival = node_metadata['is-leader'], node_metadata['is-archival']
            if int(shard) != int(machine['shard']):
                return f"configured shard {machine['shard']} != actual node shard of {shard}. (ip: {machine['ip']})"
            if condition['role'] != role:
                return f"configured node role {condition['role']} != actual node role of {role}. (ip: {machine['ip']})"
            if condition['network'] != network:
                return f"configured node network {condition['network']} != actual node network of {network}. (ip: {machine['ip']})"
            if condition['is_leader'] != is_leader:
                return f"configured node is_leader {condition['is_leader']} != actual node is_leader {is_leader}. (ip: {machine['ip']})"
            if condition['is_archival'] != is_archival:
                return f"configured node is_archival {condition['is_archival']} != actual node is_archival {is_archival}. (ip: {machine['ip']})"
            if not is_active_shard(f"http://{machine['ip']}:9500/", condition['max_seconds_since_last_block']):
                return f"one or more of the configured IPs are either offline " \
                       f"or latest block is older than {condition['max_seconds_since_last_block']} seconds"
            return None  # indicate success
        threads.append(pool.apply_async(fn))
    for t in threads:
        response = t.get()
        if response is not None:
            raise RuntimeError(response)
    log.debug('passed sanity check')


def _setup_rclone_config(machine, bash_script_path):
    """
    Worker to setup rclone on machine.
    """
    log.debug(f"setting up rclone snapshot credentials for {machine['ip']}")
    setup_response = _ssh_script(machine['user'], machine['ip'], bash_script_path)
    log.debug(f"rsync snapshot credentials setup response: {setup_response}")
    # TODO: programmatic verification
    verification_cat = _ssh_cmd(machine['user'], machine['ip'], f"cat {rsync['config_path_on_client']}")
    log.debug(f"rsync snapshot credentials on machine: {machine['ip']}: {verification_cat}")


def setup_rclone_config():
    """
    Setup rclone credentials on all the snapshot machines.

    Note that this generates a temp bash script to be executed on the snapshot machines.
    """
    threads, pool = [], ThreadPool()
    with open(rsync['config_path_on_host'], 'r') as f:
        rclone_config_raw_string = f.read()
    bash_script_content = f"""#!/bin/bash
echo "{rclone_config_raw_string}" > {rsync['config_path_on_client']}
"""
    bash_script_path = f"/tmp/snapshot_script{hash(time.time())}.sh"
    with open(bash_script_path, 'w') as f:
        f.write(bash_script_content)
    try:
        for machine in machines:
            threads.append(pool.apply_async(_setup_rclone_config, (machine, bash_script_path)))
        for t in threads:
            t.get()
    finally:
        os.remove(bash_script_path)


def _cleanup_rclone_config(machine):
    """
    Worker to cleanup rclone on machine.
    """
    log.debug(f"cleaning up rclone snapshot credentials for {machine['ip']}")
    cleanup_response = _ssh_cmd(machine['user'], machine['ip'], f"rm {rsync['config_path_on_client']}")
    log.debug(f"rsync snapshot credentials cleanup response: {cleanup_response}")
    # TODO: programmatic verification
    cmd = f"if [ -f {rsync['config_path_on_client']} ]; then echo failed cleanup; else echo successful cleanup; fi"
    verification_cat = _ssh_cmd(machine['user'], machine['ip'], cmd)
    log.debug(f"rsync snapshot credentials cleanup check: {machine['ip']}: {verification_cat}")


def cleanup_rclone_config():
    """
    Clean/remove rclone credentials that were added (as dictated by the config).

    Note that this will remove the file at whatever the `config_path_on_client`
    specifies in the config.
    """
    threads, pool = [], ThreadPool()
    for machine in machines:
        threads.append(pool.apply_async(_cleanup_rclone_config, (machine,)))
    for t in threads:
        t.get()


def _bucket_sync(machine):
    """
    Internal function to start bucket sync.
    Function call will block until bucket sync is done on machine.
    """
    log.debug(f'starting bucket sync on {machine["ip"]}')
    # TODO: bucket sync (but comment out and test last)


def _local_sync(machine):
    """
    Internal function to trigger a local sink.
    Function call will block until local sync is done on machine.
    """
    log.debug(f'starting local sync on {machine["ip"]}')
    # TODO: local sync and manually check...


def _stop_harmony(machine):
    """
    Internal function to stop and verify harmony service.
    """
    log.debug(f'stopping harmony service on {machine["ip"]}')
    machine_stop_response = _ssh_cmd(machine['user'], machine['ip'], "sudo systemctl stop harmony")
    log.debug(f'stop cmd response: {machine_stop_response}')
    off_msg = "SERVICE_STOPPED"
    cmd = f"if systemctl is-active --quiet harmony; then echo SERVICE_STARTED; else echo {off_msg}; fi"
    off_msg_response = _ssh_cmd(machine['user'], machine['ip'], cmd).strip()
    if off_msg != off_msg_response:
        log.error("harmony service failed to stop")
        log.error(f"expected msg response: {off_msg}, got: {off_msg_response}")
        raise RuntimeError("harmony service failed to stop")
    log.debug(f'successfully stopped harmony service on {machine["ip"]}')


def _start_harmony(machine):
    """
    Internal function to start and verify harmony service.
    """
    log.debug(f'starting harmony service on {machine["ip"]}')
    machine_start_resposne = _ssh_cmd(machine['user'], machine['ip'], "sudo systemctl start harmony")
    log.debug(f'start cmd response: {machine_start_resposne}')
    on_msg = "SERVICE_STARTED"
    cmd = f"if systemctl is-active --quiet harmony; then echo {on_msg}; else echo SERVICE_STOPPED; fi"
    on_msg_response = _ssh_cmd(machine['user'], machine['ip'], cmd).strip()
    if on_msg != on_msg_response:
        log.error("harmony service failed to start")
        log.error(f"expected msg response: {on_msg}, got: {on_msg_response}")
        raise RuntimeError("harmony service failed to start")
    log.debug(f'successfully started harmony service on {machine["ip"]}')


def _snapshot(machine):
    """
    Internal worker to snapshot a node's DB.

    Returns thread for bucket rsync process.
    """
    log.debug(f'started snapshot ({machine["ip"]})')
    _stop_harmony(machine)
    _local_sync(machine)
    _start_harmony(machine)
    log.debug(f'finished local snapshot ({machine["ip"]})')
    return ThreadPool().apply_async(_bucket_sync, (machine,))


def snapshot():
    """
    Execute the snapshot of the network using the given config.
    Assumes that rclone for configured `snapshot_bin` is setup on configured `machines`.
    Assumes that `sanity_check` was ran before this is called.

    Note that beacon chain will shutdown & snapshot FIRST in-order to guarantee
    that crosslinks are clean. Moreover, beacon chain is NECESSARY to generate a
    snapshot a network.
    """
    log.debug('started snapshot')
    beacon_machine = list(filter(lambda e: e['shard'] == beacon_chain_shard, machines))[0]
    aux_machines = filter(lambda e: e['shard'] != beacon_chain_shard, machines)
    threads, pool = [], ThreadPool()
    bucket_rsync_threads = [_snapshot(beacon_machine)]
    for machine in aux_machines:
        threads.append(pool.apply_async(_snapshot, (machine,)))
    for t in threads:
        bucket_rsync_threads.append(t.get())
    for t in bucket_rsync_threads:
        t.get()


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
    # TODO: make version relative to major, minor etc...
    assert pyhmy.__version__.public() == pyhmy_version, f'install correct pyhmy version with `python3 -m pip install pyhmy=={pyhmy_version}`'
    setup_logger()
    try:
        load_config(_parse_args().config)
        log.debug("initialized snapshot script")
        sanity_check()
        setup_rclone_config()
        snapshot()
        cleanup_rclone_config()
    except Exception as e:
        log.fatal(traceback.format_exc())
        log.fatal(f'script crashed with error {e}')
        exit(1)
    log.debug('finished snapshot successfully')
