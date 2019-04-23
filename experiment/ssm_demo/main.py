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


https://docs.aws.amazon.com/systems-manager/latest/userguide/integration-remote-scripts.html
aws ssm send-command --document-name "AWS-RunRemoteScript" --instance-ids "i-abcd1234" --parameters
'{"sourceType":["GitHub"],"sourceInfo":["{\"owner\":\"TestUser1\", \"repository\":\"GitHubTestPublic\", \"path\": \"scripts/python/complex-script\"}"],"commandLine":["mainFile.py argument-1 argument-2 "]}'

aws ssm send-command --document-name "AWS-RunRemoteScript" --instance-ids "i-abcd1234" --parameters'{"sourceType":["S3"],"sourceInfo":["{\"path\":\"https://s3.amazonaws.com/RubyTest/scripts/ruby/helloWorld.rb\"}"],"commandLine":["helloWorld.rb argument-1 argument-2"]}'
{"owner":"TestUser1", "repository":"GitHubPrivateTest", "path": "scripts/python/complex-script","tokenInfo":"{{ssm-secure:mySecureStringParameter}}"}


==== TROUBLESHOOTING ====
1. 	Added AWSSSMFullAccess to Andy's account
	Added ASWSSMFullAccess to `harmony-ec2-s3-role` role for Andy's cloud dev desktop

2. (?)Installed SSM agent on Andy's cloud dev desktop
	https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-manual-agent-install.html
	** After ssm agent installation, need to manually reboot the instance!!
	** Reminder: need to choose an instance type which has AWS SSM pre-installed

3. command to check if SSM agent installed on any instance
	$aws ssm describe-instance-information --output text
	https://stackoverflow.com/questions/42279963/ssm-send-command-to-ec2-instance-failed

	Command to check if SSM agent is running or not
	$sudo systemctl status amazon-ssm-agent

4. Running test againest multiple instances
    * Created an EC2 instance (based on the first given AMI in the list)
    * Created an IAM role: ssm_demo_role
        ** SSMFullAccess

"""
#!/usr/bin/env python3
import boto3
import time
import pprint

client = boto3.client('ssm', region_name='us-west-1')
# response = client.send_command(InstanceIds = ['i-05af5341989f098d7'], DocumentName = "AWS-RunShellScript", Parameters = {'commands' : ['date']})
# response = client.send_command(Targets = [{"Key" : "tag:type", "Values" : ["testnode",]},], DocumentName = "AWS-RunShellScript", Parameters = {'commands' : ['mkdir /home/ec2-user/ssm_test_Andy']})
# response = client.send_command(Targets = [{"Key" : "tag:type", "Values" : ["testnode",]},], DocumentName = "AWS-RunShellScript", Parameters = {'commands' : ['mkdir /home/ec2-user/ssm_test_Andy']})
# Parameters = '{"sourceType" : ["GitHub"], "sourceInfo" : [{\"owner\" : \"bwu2sfu\", \"repository\":\"harmony-ops\", \"path\":\"https://github.com/harmony-one/harmony-ops/blob/master/aws/ssm\"}],"commandLine" : ["nanny.sh"]}')


response = client.send_command(Targets = [{"Key" : "tag:type", "Values" : ["testnode",]},],
                               DocumentName = "AWS-RunRemoteScript",
                               Parameters = {"sourceType" : ["GitHub"], "sourceInfo" : ["{\"owner\" : \"bwu2sfu\", \"repository\":\"harmony-ops\", \"path\":\"aws/ssm\", \"getOptions\":\"branch:master\"}"],"commandLine" : ["nanny.sh"]})



# command_id = response['Command']['CommandId']

# https://stackoverflow.com/questions/50067035/retrieving-command-invocation-in-aws-ssm
time.sleep(4)

# output = client.get_command_invocation(CommandId = command_id, InstanceId = 'i-05af5341989f098d7')


print(response)