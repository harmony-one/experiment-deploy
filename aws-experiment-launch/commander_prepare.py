#!/usr/bin/env python

import argparse
import logging
import os
import stat
import sys

from utils import utils

logging.basicConfig(level=logging.INFO, format='%(threadName)s %(asctime)s - %(name)s - %(levelname)s - %(message)s')
LOGGER = logging.getLogger(__file__)
LOGGER.setLevel(logging.INFO)

PEMS = [
    "virginia-key-benchmark.pem",
    "ohio-key-benchmark.pem",
    "california-key-benchmark.pem",
    "oregon-key-benchmark.pem",
    "tokyo-key-benchmark.pem",
    "singapore-key-benchmark.pem",
    "frankfurt-key-benchmark.pem",
    "ireland-key-benchmark.pem",
]

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='This script helps you to genereate distribution config')
    parser.add_argument('--distribution_config', type=str,
                        dest='distribution_config', default='distribution_config.txt', help='file name of distribution configuration file')
    parser.add_argument('--commander_logging', type=str,
                        dest='commander_logging', default='commander_logging.sh', help='file name of commander login script')
    parser.add_argument('--log_download', type=str,
                        dest='log_download', default='download_logs_from_commander.sh', help='file name of commander log download script')
    parser.add_argument('--azure', action='store_true', dest='azure', help='pure Azure VMs')
    parser.set_defaults(azure=False)

    args = parser.parse_args()

    if not os.path.exists(args.distribution_config):
        sys.exit(1)
    with open(args.distribution_config, "r") as fin:
        lines = fin.readlines()

    commander_address = None
    commander_region = None
    commander_output = None
    with open(args.distribution_config, "w") as fout:
        for line in lines:
            if "commander" in line:
                items = [item.strip() for item in line.split(" ")]
                commander_address = items[0]
                if not args.azure:
                    commander_region = int(items[4][0])
                commander_output = "\n".join(items)
            else:
                fout.write(line.strip() + "\n")
    LOGGER.info("Generated %s" % args.distribution_config)

    if not commander_address or (not args.azure and not commander_region):
        LOGGER.info("Failed to extract commander address and commander region.")
        sys.exit(1)

    with open(args.commander_logging, "w") as fout:
        if args.azure:
            fout.write("ssh ec2-user@%s\n" % (commander_address))
        else:
            fout.write("ssh -i ../keys/%s ec2-user@%s\n" % (PEMS[commander_region - 1], commander_address))
    st = os.stat(args.commander_logging)
    os.chmod(args.commander_logging, st.st_mode | stat.S_IEXEC)
    LOGGER.info("Generated %s" % args.commander_logging)

    with open(args.log_download, "w") as fout:
        if args.azure:
            fout.write("scp -r ec2-user@%s:upload tmp\n" % (commander_address))
        else:
            fout.write("ssh -i ../keys/%s -r ec2-user@%s:upload tmp\n" % (PEMS[commander_region - 1], commander_address))
    st = os.stat(args.log_download)
    os.chmod(args.log_download, st.st_mode | stat.S_IEXEC)
    LOGGER.info("Generated %s" % args.log_download)

    LOGGER.info("DONE.")

