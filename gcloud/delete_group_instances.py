from subprocess import call, check_output
import argparse
import os
import time
import logging
import threading

logging.basicConfig(level=logging.INFO,
                    format='%(threadName)s %(asctime)s - %(name)s - %(levelname)s - %(message)s')

def getLogger(file):
    logger = logging.getLogger(file)
    logger.setLevel(logging.INFO)
    return logger
    
LOGGER = getLogger(__file__)

DELETE_CMD = [
    "gcloud",
    "compute",
    "instance-groups",
    "managed",
    "delete",
    "--zone",
    "ZONE",  # at 6
    "--quiet",
]

def delete_all_group_instances(zone, groups):
    LOGGER.info("Deleting all groups in zone %s" % zone)
    cmd = DELETE_CMD[:]
    cmd[6] = zone
    cmd.extend(groups)
    LOGGER.info("Deleting all groups in zone %s" % zone)
    ret_code = call(cmd)
    LOGGER.info("Finished deleting all groups in zone %s with return code %s" % (zone, ret_code))

def main():
    parser = argparse.ArgumentParser(
        description='This script helps create groups of instances in gcp')
    parser.add_argument('--gcp_output', type=str, dest='gcp_output',
                        default='gcp_output.txt', help='gcp group output')
    args = parser.parse_args()

    zone_to_group = {}
    for line in open(args.gcp_output).readlines():
        line = line.strip()
        if not line[:-2] in zone_to_group:
            zone_to_group[line[:-2]] = []
        zone_to_group[line[:-2]].append(line)

    thread_pool = []
    for zone, groups in zone_to_group.iteritems():
        t = threading.Thread(target=delete_all_group_instances, args=(
            zone, groups))
        t.start()
        thread_pool.append(t)
    for t in thread_pool:
        t.join()



if __name__ == '__main__':
    main()
