#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
This is the main orchestrator script to execute a snapshot with the given config.

Example Usage:
    ./snapshot.py --help
    ./snapshot.py --config ./mainnet.json
    ./snapshot.py --config ./mainnet.json --bucket-sync

Note that this script was built to be imported as a package from other scripts.
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
# Invariant: all data structures below are READ ONLY (except when loading config).
machines, rsync, ssh_key, condition, pager_duty = [], {}, {}, {}, {}  # Will be populated from config.


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
        proc.sendline(ssh_key['passphrase'])
        proc.expect(pexpect.EOF)
        log.debug(proc.before.decode())


def _ssh_cmd(user, ip, command):
    """
    Internal SSH command. Assumes ssh agent has been initialized.

    Returns the output of the SSH command.
    Raises subprocess.CalledProcessError if ssh call errored.
    """
    if ssh_key['use_existing_agent']:
        cmd = ["ssh", "-oStrictHostKeyChecking=no", f"{user}@{ip}"]
    else:
        cmd = ["ssh", "-oStrictHostKeyChecking=no", "-i", ssh_key["path"], f"{user}@{ip}"]
    cmd.append(command)
    return subprocess.check_output(cmd, env=os.environ).decode()


def _ssh_script(user, ip, bash_script_path):
    """
    Internal SSH command. Assumes ssh agent has been initialized.

    Returns the output of the SSH command.
    Raises subprocess.CalledProcessError if ssh call errored.
    """
    if ssh_key['use_existing_agent']:
        cmd = ["ssh", "-oStrictHostKeyChecking=no", f"{user}@{ip}"]
    else:
        cmd = ["ssh", "-oStrictHostKeyChecking=no", "-i", ssh_key["path"], f"{user}@{ip}"]
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
    if {'machines', 'ssh_key', 'rsync', 'condition', 'pager_duty'} != set(config.keys()):
        raise KeyError(f"config keys: {config.keys()} do not contain 'machines', "
                       f"'ssh_key', 'condition', 'pager_duty' or 'rsync'.")
    log.debug(f"config: {json.dumps(config, indent=2)}")
    machines.clear()
    rsync.clear()
    ssh_key.clear()
    condition.clear()
    pager_duty.clear()
    machines.extend(config['machines'])
    rsync.update(config['rsync'])
    ssh_key.update(config['ssh_key'])
    condition.update(config['condition'])
    pager_duty.update(config['pager_duty'])
    _init_ssh_agent()


def _is_dns_node(machine, sharding_structure):
    """
    Internal function to check if given machine is a DNS node.

    Note the assumptions in the format of the HTTP endpoint given by `sharding_structure`.

    Raises RuntimeError if endpoint cannot be found for given config.
    """
    for structure in sharding_structure:
        if int(structure['shardID']) == int(machine['shard']):
            http = structure['http'].strip()
            assert http.startswith('https://api.'), f"unknown endpoint format from machine {machine['ip']}"
            for ip in dns.resolver.query(http.replace('https://api.', '')):
                if machine['ip'] == str(ip):
                    return True
            return False
    raise RuntimeError(f"unknown shard for network (sharding structure "
                       f"endpoint not found for shard {machine['shard']})")


def sanity_check():
    """
    Enforce all given `condition` from the config as well as ensure that
    ALL nodes are alive and making progress in the first place.

    Moreover, ensure unique machines for each shard is given and that
    a beacon chain machine was given.

    All checks that require RPC calls are ran in parallel.

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
    for m in machines:
        def fn(machine):  # returning None marks success for this function
            try:
                node_metadata = blockchain.get_node_metadata(f"http://{machine['ip']}:9500/", timeout=15)
                sharding_structure = blockchain.get_sharding_structure(f"http://{machine['ip']}:9500/", timeout=15)
            except (rpc_exceptions.RPCError, rpc_exceptions.RequestsTimeoutError, rpc_exceptions.RequestsError) as e:
                log.error(traceback.format_exc())
                return f"error on RPC from {machine['ip']}. Error {e}"
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
                return f"configured node is either offline or latest block is" \
                       f" older than {condition['max_seconds_since_last_block']} seconds. (ip: {machine['ip']})"
            if _is_dns_node(machine, sharding_structure):
                return f"machine is a DNS node, which cannot be offline. (ip: {machine['ip']})"
            return None  # indicate success
        threads.append(pool.apply_async(fn, (m,)))
    for t in threads:
        response = t.get()
        if response is not None:
            raise RuntimeError(response)
    log.debug('passed sanity check')


def _setup_rclone_config(machine, bash_script_path, rclone_config_raw):
    """
    Worker to setup rclone on machine.

    Raise RuntimeError if rclone setup failed.
    """
    log.debug(f"installing rclone if needed on machine {machine['ip']} (s{machine['shard']})")
    cmd = "[ ! $(command -v rclone) ] && curl https://rclone.org/install.sh | sudo bash || echo rclone already installed"
    rclone_install_response = _ssh_cmd(machine['user'], machine['ip'], cmd)
    log.debug(f"setting up rclone snapshot credentials for {machine['ip']}")
    setup_response = _ssh_script(machine['user'], machine['ip'], bash_script_path)
    verification_cat = _ssh_cmd(machine['user'], machine['ip'], f"cat {rsync['config_path_on_client']}")
    if rclone_config_raw.strip() not in verification_cat:
        log.error(f"rclone snapshot credentials were not installed correctly")
        log.error(f"rclone install response: {rclone_install_response.strip()}")
        log.error(f"rsync credentials setup response: {setup_response.strip()}")
        log.error(f"rsync credentials on machine: {verification_cat}")
        raise RuntimeError("rclone snapshot credentials were not installed correctly")
    log.debug(f"successfully installed credentials on machine {machine['ip']} (s{machine['shard']})")


def setup_rclone_config():
    """
    Setup rclone credentials on all the snapshot machines.

    Note that this generates a temp bash script to be executed on the snapshot machines.
    """
    threads, pool = [], ThreadPool()
    with open(rsync['config_path_on_host'], 'r') as f:
        rclone_config_raw = f.read()
    bash_script_content = f"""#!/bin/bash
echo "{rclone_config_raw}" > {rsync['config_path_on_client']} && echo successfully installed config
"""
    bash_script_path = f"/tmp/snapshot_script_{time.time()}.sh"
    with open(bash_script_path, 'w') as f:
        f.write(bash_script_content)
    try:
        for machine in machines:
            threads.append(pool.apply_async(_setup_rclone_config, (machine, bash_script_path, rclone_config_raw)))
        for t in threads:
            t.get()
    finally:
        os.remove(bash_script_path)


def _cleanup_rclone_config(machine):
    """
    Worker to cleanup rclone on machine.

    Raise RuntimeError if the rclone clean up failed.
    """
    log.debug(f"cleaning up rclone snapshot credentials on {machine['ip']} (s{machine['shard']})")
    success_msg = "RCLONE_CLEANUP_SUCCESS"
    cmd = f"[ -f {rsync['config_path_on_client']} ] && rm {rsync['config_path_on_client']} && echo {success_msg} " \
          f"|| [ ! -f {rsync['config_path_on_client']} ] && echo {success_msg} "
    cleanup_response = _ssh_cmd(machine['user'], machine['ip'], cmd)
    if success_msg not in cleanup_response:
        log.error("failed to clean-up rclone config")
        log.error(f"check response: {cleanup_response.strip()}\n Expected: {success_msg}")
        raise RuntimeError("failed to clean-up rclone config")
    log.debug(f"successfully cleaned up rclone snapshot credentials on {machine['ip']} (s{machine['shard']})")


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


def _derive_db_paths(machine):
    """
    Internal function to derive the true harmony DB and
    rsync harmony DB path on the machine.
    """
    db_path_on_machine = f"{machine['db_directory']}/harmony_db_{machine['shard']}"
    db_rsync_path_on_machine = f"{db_path_on_machine}_rsync"
    return db_path_on_machine, db_rsync_path_on_machine


def _bucket_sync(machine, height):
    """
    Internal function to start bucket sync.
    Function call will block until bucket sync is done on machine.

    Note the convention used when syncing to bucket.
    """
    log.debug(f'starting bucket sync on {machine["ip"]} (s{machine["shard"]})')
    _, rsync_db_path = _derive_db_paths(machine)
    db_type = 'full' if condition['is_archival'] else 'pruned'
    bucket, shard = rsync['snapshot_bin'], machine['shard']
    time, config = datetime.datetime.utcnow().strftime("%y-%m-%d-%H-%M-%S"), rsync['config_path_on_client']
    cmd = f"rclone sync {rsync_db_path} " \
          f"{bucket}/{db_type}/{shard}/harmony_db_{shard}.{time}.{height} --config {config} -P"
    cmd_msg = None
    try:
        cmd_msg = _ssh_cmd(machine['user'], machine['ip'], cmd).strip()
    except subprocess.CalledProcessError as e:
        log.error("failed to bucket sync db")
        log.error(f"sync cmd response: {cmd_msg}")
        raise RuntimeError("failed to bucket sync db") from e
    log.debug(f'successful bucket sync on {machine["ip"]} (s{machine["shard"]})')


def _local_sync(machine):
    """
    Internal function to trigger a local sink.
    Function call will block until local sync is done on machine.
    """
    log.debug(f'starting local sync on {machine["ip"]} (s{machine["shard"]})')
    db_path_on_machine, db_rsync_path_on_machine = _derive_db_paths(machine)
    cmd = f"rclone sync {db_path_on_machine} {db_rsync_path_on_machine} --transfers 64 -P"
    cmd_msg = None
    try:
        cmd_msg = _ssh_cmd(machine['user'], machine['ip'], cmd).strip()
    except subprocess.CalledProcessError as e:
        log.error("failed to local sync db")
        log.error(f"sync cmd response: {cmd_msg}")
        raise RuntimeError("failed to local sync db") from e
    log.debug(f'successful local sync on {machine["ip"]} (s{machine["shard"]})')


def _is_harmony_running(machine):
    """
    Internal function that checks if the harmony process is running on the machine.

    Since this is a simple `pgrep` cmd, an error on the SSH implies process is not running
    as the machine is either off, or config is wrong.
    """
    try:
        _ssh_cmd(machine['user'], machine['ip'], 'pgrep harmony')
        return True
    except subprocess.CalledProcessError:
        return False


def _stop_harmony(machine):
    """
    Internal function to stop and verify harmony service.
    Assumption is that harmony is ran as a service.

    RuntimeError is raised if harmony process didn't stop after 5 seconds.
    """
    log.debug(f'stopping harmony service on {machine["ip"]} (s{machine["shard"]})')
    machine_stop_response = _ssh_cmd(machine['user'], machine['ip'], "sudo systemctl stop harmony")
    start_time = time.time()
    while time.time() - start_time < 5:
        if not _is_harmony_running(machine):
            log.debug(f'successfully stopped harmony service on {machine["ip"]} (s{machine["shard"]})')
            return
    log.error("harmony service failed to stop")
    log.error(f'stop cmd response: {machine_stop_response.strip()}')
    raise RuntimeError("harmony service failed to stop")


def _start_harmony(machine):
    """
    Internal function to start and verify harmony service.
    Assumption is that harmony is ran as a service.

    RuntimeError is raised if harmony process didn't start after 5 seconds.
    """
    log.debug(f'starting harmony service on {machine["ip"]} (s{machine["shard"]})')
    machine_start_response = _ssh_cmd(machine['user'], machine['ip'], "sudo systemctl start harmony")
    start_time = time.time()
    while time.time() - start_time < 5:
        if _is_harmony_running(machine):
            log.debug(f'successfully started harmony service on {machine["ip"]} (s{machine["shard"]})')
            return
    log.error("harmony service failed to start")
    log.debug(f'start cmd response: {machine_start_response.strip()}')
    raise RuntimeError("harmony service failed to start")


def _snapshot(machine, do_bucket_sync=False):
    """
    Internal worker to snapshot a node's DB.
    If `do_bucket_sync` is disabled, a dummy bucket_sync thread will be returned.

    Returns thread for bucket rsync process.
    """
    log.debug(f'started snapshot on machine {machine["ip"]} (s{machine["shard"]})')
    try:
        height = blockchain.get_latest_header(f"http://{machine['ip']}:9500/")['blockNumber'] if do_bucket_sync else -1
        _stop_harmony(machine)
        _local_sync(machine)
    except Exception as e:
        _start_harmony(machine)
        raise e from e
    _start_harmony(machine)
    log.debug(f'finished local snapshot on machine {machine["ip"]} (s{machine["shard"]})')
    if not do_bucket_sync:
        log.debug("skipping bucket sync...")
        return ThreadPool().apply_async(lambda: True)
    return ThreadPool().apply_async(_bucket_sync, (machine, height))


def snapshot(do_bucket_sync=False):
    """
    Execute the snapshot of the network using the given config.
    Assumes that rclone for configured `snapshot_bin` is setup on configured `machines`.
    Assumes that `sanity_check` was ran before this is called.

    If `do_bucket_sync` is enabled, an expensive sync to EXTERNAL bucket will be done.

    Note that beacon chain will shutdown & snapshot FIRST in-order to guarantee
    that crosslinks are clean. Moreover, beacon chain is NECESSARY to generate a
    snapshot a network.
    """
    log.debug('started snapshot')
    beacon_machine = list(filter(lambda e: e['shard'] == beacon_chain_shard, machines))[0]
    aux_machines = filter(lambda e: e['shard'] != beacon_chain_shard, machines)
    threads, pool = [], ThreadPool()
    bucket_rsync_threads = [_snapshot(beacon_machine, do_bucket_sync)]  # snapshot beacon chain first...
    for machine in aux_machines:
        threads.append(pool.apply_async(_snapshot, (machine, do_bucket_sync)))
    for t in threads:
        bucket_rsync_threads.append(t.get())
    for t in bucket_rsync_threads:
        t.get()


def _is_progressed_node(machine):
    """
    Internal function to check if a machine/node is making progress.
    """
    try:
        start_header = blockchain.get_latest_header(f"http://{machine['ip']}:9500/")
    except (rpc_exceptions.RPCError, rpc_exceptions.RequestsTimeoutError, rpc_exceptions.RequestsError) as e:
        log.error(traceback.format_exc())
        log.error(f"error on RPC from {machine['ip']}. Error {e}")
        return False
    start_time = time.time()
    while time.time() - start_time < condition['max_seconds_since_last_block']:
        try:
            curr_header = blockchain.get_latest_header(f"http://{machine['ip']}:9500/")
        except (rpc_exceptions.RPCError, rpc_exceptions.RequestsTimeoutError, rpc_exceptions.RequestsError) as e:
            log.error(traceback.format_exc())
            log.error(f"error on RPC from {machine['ip']}. Error {e}")
            return False
        if curr_header['blockNumber'] > start_header['blockNumber']:
            return True
        time.sleep(1)
    return False


def is_progressed_nodes():
    """
    Checks all machines in config to make sure that they are making progress.
    """
    threads, pool = [], ThreadPool()
    for machine in machines:
        threads.append(pool.apply_async(_is_progressed_node, (machine,)))
    return all(t.get() for t in threads)


def page(error):
    """
    Send page to Pager Duty.
    """
    if pager_duty['ignore']:
        log.debug("ignoring pager...")
        return
    log.debug("sending pager")
    my_ip = ''
    try:
        my_ip = requests.get('http://ipecho.net/plain').content.decode().strip()
    except Exception as e:  # catch all to page no matter what
        log.error(f'page request machine IP error {e}')
    trigger_response = Alert(pager_duty['service_key_v1']).trigger(
        description=f'Snapshot failed: {error}',
        details={
            'traceback': traceback.format_exc().strip(),
            'snapshot_machine_ip': my_ip,
            'snapshot_script_location': os.path.realpath(__file__),
            'internal_runbook': "https://app.gitbook.com/@harmony-one/s/onboarding-wiki/devops-run-book/harmony-snapshot"
        },
        client_url="https://jenkins.harmony.one/"
    )
    log.debug(f"pager trigger response: {trigger_response}")


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
    return parser.parse_args()


if __name__ == "__main__":
    assert pyhmy.__version__.major == 20
    assert pyhmy.__version__.minor >= 5
    assert pyhmy.__version__.micro >= 5
    args = _parse_args()
    setup_logger()
    try:
        load_config(args.config)
    except Exception as e:
        log.fatal(traceback.format_exc())
        log.fatal(f'snapshot startup failed with error {e}')
        page(e)
        exit(1)
    log.debug("loaded config")
    try:
        sanity_check()
        setup_rclone_config()
        snapshot(do_bucket_sync=args.bucket_sync)
        cleanup_rclone_config()
        log.debug("finished snapshot, checking for node progress...")
        if not is_progressed_nodes():
            raise RuntimeError(f"one or more node did not make progress after being started...")
    except Exception as e:
        log.fatal(traceback.format_exc())
        log.fatal(f'snapshot failed with error {e}')
        cleanup_rclone_config()
        page(e)
        exit(1)
    log.debug('HOORAY!! finished successfully')
