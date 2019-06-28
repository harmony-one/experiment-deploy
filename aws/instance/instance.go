package main

// this program is used to launch ec2 ondemain/spot instances
// todo: 10-04
//
// *. support userdata (p0) - done
// *. wait longer to launch instances (p0) - done
// *. generate instance*.txt file (p1) - done
// *. support batch launch  (p1)
// *. test of 20k/30k launch (p1)k
// *. support mixture instance type (p2) - done
// *. add launch limit in aws.json (p2)

import (
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ec2"

	//	"math"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/kr/pretty"
)

const (
	waitCountSeconds      = 30
	waitRunning           = 300 // wait for all instances report running state
	defaultRootVolumeSize = 8   // default root volume size in GiB => 8G
)

// Vpc is the struct containing VPC info
type Vpc struct {
	ID string `json:"id"`
	Sg string `json:"sg"`
}

// Ami is the struct containing AMI info
type Ami struct {
	Default string `json:"default"`
	Al2     string `json:"al2",omitempty`
}

// Limit is the struct containing spot instance limit info
type Limit struct {
	T3micro  int `json:"t3.micro"`
	T3small  int `json:"t3.small"`
	T3medium int `json:"t3.medium"`
	T3large  int `json:"t3.large"`
	T2micro  int `json:"t2.micro"`
}

// Region is the struct containg AWS Region info
type Region struct {
	Name    string `json:"name"`
	ExtName string `json:"ext-name"`
	Vpc     Vpc    `json:"vpc"`
	Ami     Ami    `json:"ami"`
	KeyPair string `json:"keypair"`
	Code    string `json:"code"`
	Limit   Limit  `json:"limit"`
}

// KeyFile is the struct to hold all key file name
type KeyFile struct {
	KeyPair string `json:"keypair"`
	KeyFile string `json:"keyfile"`
}

// UserDataStruct hold the userdata file info
type UserDataStruct struct {
	Name string `json:"name"`
	File string `json:"file"`
}

// InstancePrice hold the price per instance type
type InstancePrice struct {
	Name  string  `json:"name"`
	Price float64 `json:"price"`
}

// AWSRegions is the struct to serialize/deserialize AWS Region data
type AWSRegions struct {
	Regions   []*Region         `json:"regions"`
	KeyFiles  []*KeyFile        `json:"keyfiles"`
	UserData  []*UserDataStruct `json:"userdata"`
	Instances []*InstancePrice  `json:"instance"`
}

// InstanceConfig is the instance info for launch
type InstanceConfig struct {
	RegionName string `json:"region"`
	Type       string `json:"type"`
	Number     int    `json:"ondemand"`
	Spot       int    `json:"spot"`
	AmiName    string `json:"ami",omitempty`
	Root       int64  `json:"root",omitempty`
}

// LaunchConfig is the struct having all launch configuration
type LaunchConfig struct {
	RegionInstances []*InstanceConfig `json:"launch"`
	UserData        *UserDataStruct   `json:"userdata"`
	Batch           int               `json:"batch"`
}

type instType int

func (i instType) String() string {
	switch i {
	case onDemand:
		return "onDemand"
	case spot:
		return "Spot"
	}
	return "Unknown"
}

const (
	onDemand instType = iota
	spot     instType = iota
)

var (
	version string
	builtBy string
	builtAt string
	commit  string
)

var (
	whoami = os.Getenv("WHOAMI")
	t      = time.Now()
	now    = fmt.Sprintf("%d-%02d-%02d_%02d_%02d_%02d", t.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second())

	configDir     = flag.String("config_dir", "../configs", "the directory of all the configuration files")
	launchProfile = flag.String("launch_profile", "launch-10.json", "the profile name for instance launch")
	awsProfile    = flag.String("aws_profile", "aws.json", "the profile of the aws configuration")
	debug         = flag.Int("debug", 0, "enable debug output level")
	tag           = flag.String("tag", whoami, "a tag in instance name")
	versionFlag   = flag.Bool("version", false, "Output version info")
	outputFile    = flag.String("output", "instance_ids_output.txt", "file name of instance ids")
	tagFile       = flag.String("tag_file", "instance_output.txt", "file name of tags used to terminate instances")
	ipFile        = flag.String("ip_file", "raw_ip.txt", "file name of ip addresses of instances")
	instanceType  = flag.String("instance_type", "t3.micro", "type of the instance, will override profile")
	instanceCount = flag.Int("instance_count", 0, "number of instance to be launched in each region, will override profile")
	launchRegion  = flag.String("launch_region", "pdx", "list of regions, separated by ',', will override profile")
	rootVolume    = flag.Int64("root_volume", 0, "the size of the root volume in GB, will override profile")
	protection    = flag.Bool("protection", false, "protect on-demand instance from termination")

	userDataString string

	myInstances    sync.Map
	myInstancesID  sync.Map
	myInstancesTag sync.Map

	wg sync.WaitGroup

	messages = make(chan string)

	totalInstances int
)

func printVersion(me string) {
	fmt.Fprintf(os.Stderr, "Harmony (C) 2018. %v, version %v-%v (%v %v)\n", path.Base(me), version, commit, builtBy, builtAt)
	os.Exit(0)
}

func debugOutput(level int, msg interface{}) {
	if *debug > level {
		fmt.Println(pretty.Formatter(msg))
	}
}

func exitErrorf(msg string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, msg+"\n", args...)
	fmt.Fprintf(os.Stderr, "\n")
	os.Exit(1)
}

func parseAWSRegionConfig(config string) (*AWSRegions, error) {
	data, err := ioutil.ReadFile(config)
	if err != nil {
		return nil, fmt.Errorf("can't read file (%v): %v", config, err)
	}
	if !json.Valid(data) {
		return nil, fmt.Errorf("invalid json data %s", data)
	}
	regionConfig := new(AWSRegions)
	if err := json.Unmarshal(data, regionConfig); err != nil {
		return nil, fmt.Errorf("can't parse AWs regions config (%v): %v", config, err)
	}
	return regionConfig, nil
}

func parseLaunchConfig(config string) (*LaunchConfig, error) {
	data, err := ioutil.ReadFile(config)
	if err != nil {
		return nil, fmt.Errorf("Can't read file (%v): %v", config, err)
	}
	if !json.Valid(data) {
		return nil, fmt.Errorf("invalid json data %s", data)
	}
	launchConfig := new(LaunchConfig)
	if err := json.Unmarshal(data, launchConfig); err != nil {
		return nil, fmt.Errorf("can't unmarshal launch config (%v): %v", config, err)
	}
	return launchConfig, nil
}

func findAMI(region *Region, amiName string) (string, error) {
	switch amiName {
	case "al2":
		return region.Ami.Al2, nil
	default:
		return region.Ami.Default, nil
	}
	return "", fmt.Errorf("Can't find the right AMI: %v", amiName)
}

// return the struct pointer to the region based on name
func findRegion(regions *AWSRegions, name string) (*Region, error) {
	for _, r := range regions.Regions {
		if strings.Compare(r.Name, name) == 0 {
			return r, nil
		}
	}

	return nil, fmt.Errorf("Can't find the region: %v", name)
}

func findSubnet(svc *ec2.EC2, vpc Vpc) ([]*ec2.Subnet, error) {

	input := &ec2.DescribeSubnetsInput{
		Filters: []*ec2.Filter{
			{
				Name: aws.String("vpc-id"),
				Values: []*string{
					aws.String(vpc.ID),
				},
			},
		},
	}

	subnets, err := svc.DescribeSubnets(input)

	if err != nil {
		return nil, fmt.Errorf("DescribeSubnets Error: %v", err)
	}

	debugOutput(1, subnets)

	return subnets.Subnets, nil
}

func getPrice(aws *AWSRegions, insttype string) float64 {
	for _, i := range aws.Instances {
		if strings.Compare(i.Name, insttype) == 0 {
			return i.Price
		}
	}
	return 0
}

func getInstancesInput(reg *Region, i *InstanceConfig, regs *AWSRegions, instType instType) (*ec2.RunInstancesInput, error) {

	amiID, err := findAMI(reg, i.AmiName)
	if err != nil {
		messages <- fmt.Sprintf("%v: findAMI Error %v", reg.Name, err)
		return nil, fmt.Errorf("findAMI Error %v", err)
	}

	var input ec2.RunInstancesInput
	if i.Root == 0 {
		i.Root = defaultRootVolumeSize
	}
	if *rootVolume != 0 {
		i.Root = *rootVolume
	}

	root := ec2.EbsBlockDevice{
		VolumeSize: aws.Int64(i.Root),
	}

	switch instType {
	case onDemand:
		tagValue := fmt.Sprintf("%s-%s-od-%s", reg.Code, *tag, now)

		input = ec2.RunInstancesInput{
			ImageId:          aws.String(amiID),
			InstanceType:     aws.String(i.Type),
			MinCount:         aws.Int64(1),
			MaxCount:         aws.Int64(int64(i.Number)),
			KeyName:          aws.String(reg.KeyPair),
			SecurityGroupIds: []*string{aws.String(reg.Vpc.Sg)},
			TagSpecifications: []*ec2.TagSpecification{
				{
					ResourceType: aws.String("instance"),
					Tags: []*ec2.Tag{
						{
							Key:   aws.String("Name"),
							Value: aws.String(tagValue),
						},
					},
				},
			},
			UserData: &userDataString,
			BlockDeviceMappings: []*ec2.BlockDeviceMapping{
				{
					DeviceName: aws.String("/dev/xvda"),
					Ebs:        &root,
				},
			},
		}
		if _, ok := myInstancesTag.Load(tagValue); !ok {
			myInstancesTag.Store(tagValue, reg.Code)
		}
		totalInstances += i.Number

	case spot:
		tagValue := fmt.Sprintf("%s-%s-spot-%s", reg.Code, *tag, now)

		input = ec2.RunInstancesInput{
			ImageId:      aws.String(amiID),
			InstanceType: aws.String(i.Type),

			InstanceMarketOptions: &ec2.InstanceMarketOptionsRequest{
				MarketType: aws.String("spot"),
				SpotOptions: &ec2.SpotMarketOptions{
					MaxPrice: aws.String(strconv.FormatFloat(getPrice(regs, i.Type), 'g', 10, 64)),
				},
			},

			MinCount:         aws.Int64(1),
			MaxCount:         aws.Int64(int64(i.Spot)),
			KeyName:          aws.String(reg.KeyPair),
			SecurityGroupIds: []*string{aws.String(reg.Vpc.Sg)},
			TagSpecifications: []*ec2.TagSpecification{
				{
					ResourceType: aws.String("instance"),
					Tags: []*ec2.Tag{
						{
							Key:   aws.String("Name"),
							Value: aws.String(tagValue),
						},
					},
				},
			},
			UserData: &userDataString,
			BlockDeviceMappings: []*ec2.BlockDeviceMapping{
				{
					DeviceName: aws.String("/dev/xvda"),
					Ebs:        &root,
				},
			},
		}
		if _, ok := myInstancesTag.Load(tagValue); !ok {
			myInstancesTag.Store(tagValue, reg.Code)
		}
		totalInstances += i.Spot
	}
	enableMonitoring := (&ec2.RunInstancesMonitoringEnabled{}).SetEnabled(false)
	input.SetMonitoring(enableMonitoring)
	iamProfile := (&ec2.IamInstanceProfileSpecification{})
	iamProfile.SetName("harmony-node-instance")
	input.SetIamInstanceProfile(iamProfile)

	debugOutput(1, input)

	return &input, nil
}

func launchInstances(i *InstanceConfig, regs *AWSRegions, instType instType) error {
	defer wg.Done()

	reg, err := findRegion(regs, i.RegionName)
	if err != nil {
		return fmt.Errorf("findRegion Error: %v", err)
	}

	messages <- fmt.Sprintf("launching %s instances in region: %v", instType, reg.Name)

	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(reg.ExtName)},
	)
	if err != nil {
		messages <- fmt.Sprintf("%v: aws session Error: %v", reg.Name, err)
		return fmt.Errorf("aws session Error: %v", err)
	}

	// Create an EC2 service client.
	svc := ec2.New(sess)

	var reservations []*string

	input, err := getInstancesInput(reg, i, regs, instType)

	start := time.Now()

	reservation, err := svc.RunInstances(input)

	if err != nil {
		messages <- fmt.Sprintf("%v: run instance error: %v", reg.Name, err)
		return err
	}

	debugOutput(0, reservation)

	reservations = append(reservations, reservation.ReservationId)

	instanceInput := &ec2.DescribeInstancesInput{
		Filters: []*ec2.Filter{
			&ec2.Filter{
				Name:   aws.String("reservation-id"),
				Values: reservations,
			},
		},
	}

	messages <- fmt.Sprintf("%v/%s: sleeping for %d seconds before get IP ...", reg.Name, instType, waitCountSeconds)
	time.Sleep(waitCountSeconds * time.Second)

	num := 0

	/* wait to get all the public IP address */
	/* wait until mininum number of instance */

	waitStart := time.Now()
	for duration := 0; num < int(*input.MaxCount) && duration < waitRunning; duration = int(time.Since(waitStart).Seconds()) {
		result, err := svc.DescribeInstances(instanceInput)

		if err != nil {
			messages <- fmt.Sprintf("DescribeInstances Error: %v", err)
		}

		/*
			token := result.NextToken
			if *debug > 2 {
				fmt.Printf("describe instances next token: %v\n", token)
			}
		*/
		for _, r := range result.Reservations {
			for _, inst := range r.Instances {
				if inst != nil && inst.PublicIpAddress != nil && *inst.PublicIpAddress != "" {
					if instType != spot && *protection { // protect the on-demand instance
						input := &ec2.ModifyInstanceAttributeInput{
							InstanceId: inst.InstanceId,
							DisableApiTermination: &ec2.AttributeBooleanValue{
								Value: aws.Bool(true),
							},
						}
						_, err := svc.ModifyInstanceAttribute(input)
						if err != nil {
							if aerr, ok := err.(awserr.Error); ok {
								switch aerr.Code() {
								default:
									fmt.Println(aerr.Error())
								}
							} else {
								// Print the error, cast err to awserr.Error to get the Code and
								// Message from an error.
								fmt.Println(err.Error())
							}
						}
					}
					if _, ok := myInstances.Load(*inst.PublicIpAddress); !ok {
						for _, t := range inst.Tags {
							if *t.Key == "Name" {
								myInstancesID.Store(*inst.InstanceId, *t.Value)
								myInstances.Store(*inst.PublicIpAddress, *t.Value)
								break
							}
						}
						num++
					}
				} else {
					time.Sleep(1 * time.Second)
				}
			}
		}
	}

	debugOutput(2, myInstances)

	messages <- fmt.Sprintf("%v: %d/%d %s instances (used %v)", reg.Name, num, totalInstances, instType, time.Since(start))
	return nil
}

func saveOutput() {
	ipf, err := os.Create(*ipFile)
	if err != nil {
		fmt.Printf("Can't open file %s to write. %v", *ipFile, err)
		return
	}
	defer ipf.Close()

	f, err := os.Create(*outputFile)
	if err != nil {
		fmt.Printf("Can't open file %s to write. %v", *outputFile, err)
		return
	}
	defer f.Close()

	f1, err := os.Create(*tagFile)
	if err != nil {
		fmt.Printf("Can't open file %s to write. %v", *tagFile, err)
		return
	}
	defer f1.Close()

	myInstances.Range(func(k, v interface{}) bool {
		_, err := ipf.Write([]byte(fmt.Sprintf("%v %v\n", k, v)))
		if err != nil {
			fmt.Printf("Write to file error %v", err)
			return false
		}
		return true
	})
	myInstancesID.Range(func(k, v interface{}) bool {
		_, err := f.Write([]byte(fmt.Sprintf("%v %v\n", k, v)))
		if err != nil {
			fmt.Printf("Write to file error %v", err)
			return false
		}
		return true
	})
	myInstancesTag.Range(func(k, v interface{}) bool {
		_, err := f1.Write([]byte(fmt.Sprintf("%v %v\n", k, v)))
		if err != nil {
			fmt.Printf("Write to file error %v", err)
			return false
		}
		return true
	})
}

func main() {
	flag.Parse()

	if *versionFlag {
		printVersion(os.Args[0])
	}

	if *tag == "" {
		whoami = os.Getenv("USER")
		tag = &whoami
	}

	regions, err := parseAWSRegionConfig(filepath.Join(*configDir, *awsProfile))
	if err != nil {
		exitErrorf("Exiting ... : %v", err)
	}

	launches, err := parseLaunchConfig(filepath.Join(*configDir, *launchProfile))
	if err != nil {
		exitErrorf("Exiting ... : %v", err)
	}

	debugOutput(0, launches.RegionInstances)

	if data, err := ioutil.ReadFile(filepath.Join(*configDir, launches.UserData.File)); err != nil {
		exitErrorf("Exiting ... : %v", err)
	} else {
		userDataString = base64.StdEncoding.EncodeToString(data)
		debugOutput(2, userDataString)
	}

	start := time.Now()

	if *instanceCount != 0 {
		regionList := strings.Split(*launchRegion, ",")
		for _, r := range regionList {
			rc := InstanceConfig{
				RegionName: r,
				Type:       *instanceType,
				Number:     *instanceCount,
				Spot:       0,
				AmiName:    "default",
			}
			wg.Add(1)
			go launchInstances(&rc, regions, onDemand)
		}
	} else {
		for _, r := range launches.RegionInstances {
			if r.Number > 0 {
				wg.Add(1)
				go launchInstances(r, regions, onDemand)
			}
			if r.Spot > 0 {
				wg.Add(1)
				go launchInstances(r, regions, spot)
			}
		}
	}
	go func() {
		for i := range messages {
			fmt.Println(i)
		}
	}()
	wg.Wait()

	saveOutput()

	fmt.Println("Total Used: ", time.Since(start))
}
