#Introduction
This document describes the structure and explain the variables of the launch-xxx.json files.
This file is only used to control the launch of AWS EC2 instances.

##launch
This section defines a list of region and the instance launch options in each region.
Noted this is a list of json struct in this variable.  And you may have multiple struct for one region defined.

###launch.region
* string
* This is the name of the AWS region. AWS internally uses the 3 letter airport code to represent each region.
* The official list of AWS region is [Here](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.RegionsAndAvailabilityZones.html)
* You may find a complete list of AWS region code in the [aws.json file](https://github.com/harmony-one/experiment-deploy/blob/master/configs/aws.json)

###launch.type
* string
* This is the type of EC2 instance to be launched in this region.

###launch.ondemand
* integer
* This defines the number of on-demand instances to be launched.

###launch.ami
* string
* The AMI name to be launched. The AMI name can be found in the aws.json file as well.

###launch.spot
* integer
* The number of spot instances to be launched in the region.

##userdata
This section defines the userdata for each instance.

###userdata.name
* string
* "http" is the new way to control the soldier via HTTP REST api.

###userdata.file
* string
* The file name of the user data template.

##batch
* integer
* The number of instances launched per batch. If we need to launch a huge number of instance, we may increase this number.

#Sample
[Devnet Launch Configuration JSON file](https://docs.google.com/document/d/1ijvu5Bud83AuT9rDC2AaqZlpKMVUqHn9BqP6d3TZRGM/)
