#!/usr/bin/env python

import argparse
import base64
import boto3
import datetime
import json
import sys
import threading
import time
import enum

#TODO REMOVE UTILS
from utils import utils, spot_fleet, logger

LOGGER = logger.getLogger(__file__)
REGION_NAME = 'region_name'
REGION_KEY = 'region_key'
REGION_SECURITY_GROUP = 'region_security_group'
REGION_SECURITY_GROUP_ID = 'region_security_group_id'
REGION_HUMAN_NAME = 'region_human_name'
INSTANCE_TYPE = 't2.micro'
REGION_AMI = 'region_ami'


class InstanceResource(enum.Enum):
    ON_DEMAND = 'ondemand'
    SPOT_INSTANCE = 'spot'
    SPOT_FLEET = 'fleet'

    def __str__(self):
        return self.value


def run_one_region_on_demand_instances(profile, config, region_number, number_of_instances, node_name):
    ec2_client = utils.create_client(profile, config, region_number)
    err = create_instances(
        config, ec2_client, region_number, number_of_instances, node_name)
    LOGGER.info("Created %s in region %s" % (node_name, region_number))
    return err, ec2_client


def create_instances(config, ec2_client, region_number, number_of_instances, node_name):
    # Returns true on error, false on success
    LOGGER.info("Creating nodes with name: %s" % node_name)
    available_zone = utils.get_one_availability_zone(ec2_client)
    LOGGER.info("Looking at zone %s to create instances." % available_zone)

    time.sleep(2)
    ec2_client.run_instances(
        MinCount=number_of_instances,
        MaxCount=number_of_instances,
        ImageId=config[region_number][utils.REGION_AMI],
        Placement={
            'AvailabilityZone': available_zone,
        },
        SecurityGroups=[config[region_number][utils.REGION_SECURITY_GROUP]],
        IamInstanceProfile={
            'Name': utils.IAM_INSTANCE_PROFILE
        },
        KeyName=config[region_number][utils.REGION_KEY],
        UserData=utils.USER_DATA,
        InstanceType=INSTANCE_TYPE,
        TagSpecifications=[
            {
                'ResourceType': 'instance',
                'Tags': [
                    {
                        'Key': 'Name',
                        'Value': node_name
                    },
                ]
            },
        ],
    )

    retry_count = 10
    while retry_count > 0:
        try:
            time.sleep(20)
            instance_ids = utils.get_instance_ids2(ec2_client, node_name)
            LOGGER.info("Waiting for all %d instances in region %s with node_name %s to be in RUNNING" % (
                len(instance_ids), region_number, node_name))
            break
        except:
            retry_count -= 1
            LOGGER.info("Failed to get instance ids. Retry again.")
    retry_count = 10
    while retry_count > 0:
        try:
            time.sleep(20)
            waiter = ec2_client.get_waiter('instance_running')
            waiter.wait(InstanceIds=instance_ids)
            break
        except:
            retry_count -= 1
            LOGGER.info("Failed to wait.")

    retry_count = 10
    while retry_count > 0:
        time.sleep(20)
        LOGGER.info("Waiting ...")
        ip_list = utils.collect_public_ips_from_ec2_client(
            ec2_client, node_name)
        if len(ip_list) == number_of_instances:
            LOGGER.info("Created %d instances" % number_of_instances)
            return False
        retry_count -= 10
    LOGGER.info("Can not get %d instances" % number_of_instances)
    return True


LOCK_FOR_RUN_ONE_REGION = threading.Lock()


def run_for_one_region_on_demand(profile, config, region_number, number_of_instances, tag, fout, fout2):
    batch_index = 0
    number_of_instances = int(number_of_instances)
    while number_of_instances > 0:
        number_of_creation = min(
            utils.MAX_INSTANCES_FOR_DEPLOYMENT, number_of_instances)
        node_name = utils.get_node_name(region_number, str(batch_index), tag)
        err, ec2_client = run_one_region_on_demand_instances(
            profile, config, region_number, number_of_creation, node_name)
        if not err:
            LOGGER.info("Managed to create instances for region %s with node_name %s" %
                        (region_number, node_name))
            instance_ids = utils.get_instance_ids2(ec2_client, node_name)
            LOCK_FOR_RUN_ONE_REGION.acquire()
            try:
                fout.write("%s %s\n" % (node_name, region_number))
                for instance_id in instance_ids:
                    fout2.write(instance_id + " " + node_name + " " + region_number +
                                " " + config[region_number][utils.REGION_NAME] + "\n")
            finally:
                LOCK_FOR_RUN_ONE_REGION.release()
        else:
            LOGGER.info("Failed to create instances for region %s" %
                        region_number)
        number_of_instances -= number_of_creation
        batch_index += 1


def read_region_config(region_config='configuration.txt'):
    global CONFIG
    config = {}
    with open(region_config, 'r') as f:
        for myline in f:
            mylist = [item.strip() for item in myline.strip().split(',')]
            region_num = mylist[0]
            config[region_num] = {}
            config[region_num][REGION_NAME] = mylist[1]
            config[region_num][REGION_KEY] = mylist[2]
            config[region_num][REGION_SECURITY_GROUP] = mylist[3]
            config[region_num][REGION_HUMAN_NAME] = mylist[4]
            config[region_num][REGION_AMI] = mylist[5]
            config[region_num][REGION_SECURITY_GROUP_ID] = mylist[6]
    CONFIG = config
    return config


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description='This script helps you start instances across multiple regions')
    parser.add_argument('--regions', type=str, dest='regions',
                        default='3', help="Supply a csv list of all regions")
    parser.add_argument('--instances', type=str, dest='num_instance_list',
                        default='1', help='number of instances in respective of region')
    parser.add_argument('--region_config', type=str,
                        dest='region_config', default='configuration.txt')
    parser.add_argument('--instance_output', type=str, dest='instance_output',
                        default='instance_output.txt', help='the file to append or write')
    parser.add_argument('--instance_ids_output', type=str, dest='instance_ids_output',
                        default='instance_ids_output.txt', help='the file to append or write')
    parser.add_argument('--instance_resource', dest='instance_resource', type=InstanceResource,
                        default=InstanceResource.ON_DEMAND, choices=list(InstanceResource))
    parser.add_argument('--append', dest='append', type=bool, default=False,
                        help='append to the current instance_output')
    parser.add_argument('--profile', type=str, dest='aws_profile', default='default',
                        help='set the aws profile name')
    parser.add_argument('--instancetype', type=str, dest='instance', default='t2.micro',
                        help='set the aws instance type')
    parser.add_argument('--userdata', type=str, dest='userdata', default='configs/userdata-soldier.sh',
                        help='set the filename of userdata')
    parser.add_argument('--tag', type=str, dest='tag', default='',
                        help='customized tag value')
    args = parser.parse_args()

    INSTANCE_TYPE = args.instance
    utils.get_user_data(args.userdata)

    config = read_region_config(args.region_config)
    region_list = args.regions.split(',')
    num_instance_list = args.num_instance_list.split(',')
    instance_resource = args.instance_resource
    assert len(region_list) == len(num_instance_list), "number of regions: %d != number of instances per region: %d" % (
        len(region_list), len(num_instance_list))

    write_mode = "a" if args.append else "w"
    with open(args.instance_output, write_mode) as fout, open(args.instance_ids_output, write_mode) as fout2:
        thread_pool = []
        for i in range(len(region_list)):
            region_number = region_list[i]
            number_of_instances = num_instance_list[i]
            if instance_resource == InstanceResource.ON_DEMAND:
                t = threading.Thread(target=run_for_one_region_on_demand, args=(
                    args.aws_profile, config, region_number, number_of_instances, args.tag, fout, fout2))
            elif instance_resource == InstanceResource.SPOT_FLEET:
                t = threading.Thread(target=spot_fleet.run_one_region, args=(
                    region_number, number_of_instances, fout, fout2))
            LOGGER.info("creating thread for region %s" % region_number)
            t.start()
            thread_pool.append(t)
        for t in thread_pool:
            t.join()
        LOGGER.info("done.")
