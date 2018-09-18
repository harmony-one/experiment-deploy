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

INSTANCE_TEMPALTE = "benchmark-template-micro-soldier-http-minhdoan-1"


# gcloud compute instance-groups managed create test --base-instance-name morning --size 50 --template benchmark-template-micro --zone us-west1-a
CREATE_COMMMAND = [
    "gcloud",
    "compute",
    "instance-groups",
    "managed",
    "create",
    "NAME",  # name at 5
    "--base-instance-name",
    "BASE_NAME", # base name at 7
    "--size",
    "100", # size at 9
    "--template",
    INSTANCE_TEMPALTE, # instance type
    "--zone",
    "ZONE", # zone at 13
]

# gcloud compute instance-groups managed wait-until-stable NAME

WAIT_COMMAND = [
    "gcloud",
    "compute",
    "instance-groups",
    "managed",
    "wait-until-stable",
    "NAME", # name at 5
    "--timeout",
    "TIME_OUT", # time_out at 7
    "--zone",
    "ZONE", # zone at 9
]

# ZONE_INSTANCES = {
#     'asia-southeast1-b': 1500,
#     'asia-southeast1-c': 1500,
#     'asia-east1-c': 3000,
#     'europe-west4-b': 2000,
#     'europe-west4-c': 2000,
#     'europe-north1-a': 1333,
#     'europe-north1-b': 1333,
#     'europe-north1-c': 1333,
#     'us-central1-f': 3000,
#     'us-west1-c': 3000,
# }

ZONE_INSTANCES = {
    # 'asia-southeast1-b': 15,
    # 'asia-southeast1-c': 15,
    # 'asia-east1-c': 30,
    # 'europe-west4-b': 20,
    # 'europe-west4-c': 20,
    'europe-north1-a': 13,
    'europe-north1-b': 13,
    'europe-north1-c': 13,
    'us-central1-f': 30,
    'us-west1-c': 30,
}

MAX_PER_ZONE = 10

def create_group_instances(name, base_name, zone, size, time_out):
    cmd = CREATE_COMMMAND[:]
    cmd[5] = name
    cmd[7] = base_name
    cmd[9] = str(size)
    cmd[13] = zone
    LOGGER.info("Run creating a group of instances %s with base name %s at zone %s with size %s" % (name, base_name, zone, size))
    ret_code = call(cmd)
    LOGGER.info("Finished creating a group of instances %s with base name %s at zone %s with size %s with return_code %s" % (name, base_name, zone, size, ret_code))

def wait_one_group_instances(name, zone, time_out):
    cmd = WAIT_COMMAND[:]
    cmd[5] = name
    cmd[7] = str(time_out)
    cmd[9] = zone
    LOGGER.info("Run creating a group of instances %s at zone %s with time out %s" % (name, zone, time_out))
    ret_code = call(cmd)
    LOGGER.info("Finished creating a group of instances %s at zone %s with time out %s with return code %s" % (name, zone, time_out, ret_code))

def wait_all_group_instances(zone, number_of_instances):
    id = 0
    cur = number_of_instances
    thread_pool = []
    while cur > 0:
        instances_to_launch = min(cur, MAX_PER_ZONE)
        name = "%s-%s" % (zone, id)
        t = threading.Thread(target=wait_one_group_instances,
                             args=(name, zone, 300))
        t.start()
        thread_pool.append(t)
        cur -= instances_to_launch
        id += 1
    for t in thread_pool:
        t.join()

def create_all_group_instances(zone, number_of_instances):
    id = 0
    cur = number_of_instances
    while cur > 0:
        instances_to_launch = min(cur, MAX_PER_ZONE)
        name = "%s-%s" % (zone, id)
        base_name = "morning"
        create_group_instances(name, base_name, zone, instances_to_launch, 300)
        cur -= instances_to_launch
        id += 1
    wait_all_group_instances(zone, number_of_instances)

def generate_gcp_output(fout_name):
    with open(fout_name, "w") as fout:
        for zone, number_of_instances in ZONE_INSTANCES.iteritems():
            cur = int(number_of_instances)
            id = 0
            while cur > 0:
                instances_to_launch = min(cur, MAX_PER_ZONE)
                name = "%s-%s" % (zone, id)
                fout.write("%s\n" % name)
                cur -= instances_to_launch
                id += 1

def main():
    parser = argparse.ArgumentParser(
        description='This script helps create groups of instances in gcp')
    parser.add_argument('--gcp_output', type=str, dest='gcp_output',
                        default='gcp_output.txt', help='gcp group output')
    args = parser.parse_args()

    thread_pool = []
    for zone, number_of_instances in ZONE_INSTANCES.iteritems():
        number_of_instances = int(number_of_instances)
        t = threading.Thread(target=create_all_group_instances, args=(
            zone, number_of_instances))
        t.start()
        thread_pool.append(t)
    for t in thread_pool:
        t.join()
    generate_gcp_output(args.gcp_output)
    LOGGER.info("done.")

if __name__ == '__main__':
    main()
