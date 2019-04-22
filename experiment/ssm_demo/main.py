"""
AWS Systems Manager Demo

Author: Andy Bo Wu
Date: Apr 21, 2019

==== PURPOSE ====
The current `solider` design does the job, but AWS also has a service called AWS Systems Manager, or \
Simple Systems Manager (SSM). It allows system admins to run scripts, do inventory state check, etc \
without SSh/RDP to the instances. 

This script will take advanage to SSM, download a sample bash script from S3, and run the script on the \
instances.  

==== USAGE ====


==== VERSION ====

1. APR 21, 2019     
    * Created the script





"""

# !/usr/bin/env python3
import boto3
import sys