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
	//	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ec2"

	//	"math"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"github.com/kr/pretty"
	"io/ioutil"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	WAIT_COUNT   = 60
	WAIT_RUNNING = 300 // wait for all instances report running state
)

type Vpc struct {
	Id string `json:"id"`
	Sg string `json:"sg"`
}

type Ami struct {
	Default string `json:"default"`
	Al2     string `json:"al2",omitempty`
}

type Region struct {
	Name    string `json:"name"`
	ExtName string `json:"ext-name"`
	Vpc     Vpc    `json:"vpc"`
	Ami     Ami    `json:"ami"`
	KeyPair string `json:"keypair"`
	Code    string `json:"code"`
}

type KeyFile struct {
	KeyPair string `json:"keypair"`
	KeyFile string `json:"keyfile"`
}

type UserDataStruct struct {
	Name string `json:"name"`
	File string `json:"file"`
}

type InstancePrice struct {
	Name  string  `json:"name"`
	Price float64 `json:"price"`
}

type AWSRegions struct {
	Regions   []*Region         `json:"regions"`
	KeyFiles  []*KeyFile        `json:"keyfiles"`
	UserData  []*UserDataStruct `json:"userdata"`
	Instances []*InstancePrice  `json:"instance"`
}

type InstanceConfig struct {
	RegionName string `json:"region"`
	Type       string `json:"type"`
	Number     int    `json:"ondemand"`
	Spot       int    `json:"spot"`
	AmiName    string `json:"ami",omitempty`
}

type LaunchConfig struct {
	RegionInstances []*InstanceConfig `json:"launch"`
	UserData        *UserDataStruct   `json:"userdata"`
	Batch           int               `json:"batch"`
}

type InstType int

func (i InstType) String() string {
	switch i {
	case OnDemand:
		return "OnDemand"
	case Spot:
		return "Spot"
	}
	return "Unknown"
}

const (
	OnDemand InstType = iota
	Spot     InstType = iota
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

	userDataString string

	myInstances    sync.Map
	myInstancesId  sync.Map
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
		return nil, errors.New(fmt.Sprintf("Can't read file (%v): %v", config, err))
	}
	if !json.Valid(data) {
		return nil, errors.New(fmt.Sprintf("Invalid Json data %s!", data))
	}
	regionConfig := new(AWSRegions)
	if err := json.Unmarshal(data, regionConfig); err != nil {
		return nil, errors.New(fmt.Sprintf("Can't parse AWs regions config (%v): %v", config, err))
	}
	return regionConfig, nil
}

func parseLaunchConfig(config string) (*LaunchConfig, error) {
	data, err := ioutil.ReadFile(config)
	if err != nil {
		return nil, errors.New(fmt.Sprintf("Can't read file (%v): %v", config, err))
	}
	if !json.Valid(data) {
		return nil, errors.New(fmt.Sprintf("Invalid Json data %s!", data))
	}
	launchConfig := new(LaunchConfig)
	if err := json.Unmarshal(data, launchConfig); err != nil {
		return nil, errors.New(fmt.Sprintf("Can't Unmarshal launch config (%v): %v", config, err))
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
					aws.String(vpc.Id),
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

func getInstancesInput(reg *Region, i *InstanceConfig, regs *AWSRegions, instType InstType) (*ec2.RunInstancesInput, error) {

	amiId, err := findAMI(reg, i.AmiName)
	if err != nil {
		messages <- fmt.Sprintf("%v: findAMI Error %v", reg.Name, err)
		return nil, fmt.Errorf("findAMI Error %v", err)
	}

	var input ec2.RunInstancesInput

	switch instType {
	case OnDemand:
		tagValue := fmt.Sprintf("%s-%s-od-%s", reg.Code, *tag, now)

		input = ec2.RunInstancesInput{
			ImageId:          aws.String(amiId),
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
		}
		if _, ok := myInstancesTag.Load(tagValue); !ok {
			myInstancesTag.Store(tagValue, reg.Code)
		}
		totalInstances += i.Number

	case Spot:
		tagValue := fmt.Sprintf("%s-%s-spot-%s", reg.Code, *tag, now)

		input = ec2.RunInstancesInput{
			ImageId:      aws.String(amiId),
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
		}
		if _, ok := myInstancesTag.Load(tagValue); !ok {
			myInstancesTag.Store(tagValue, reg.Code)
		}
		totalInstances += i.Spot
	}

	debugOutput(1, input)

	return &input, nil
}

func launchInstances(i *InstanceConfig, regs *AWSRegions, instType InstType) error {
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

	messages <- fmt.Sprintf("%v/%s: sleeping for %d seconds ...", reg.Name, instType, WAIT_COUNT)
	time.Sleep(WAIT_COUNT * time.Second)

	num := 0

	/* wait to get all the public IP address */
	/* wait until mininum number of instance */

	wait_start := time.Now()
	for duration := 0; num < int(*input.MaxCount) && duration < WAIT_RUNNING; duration = int(time.Since(wait_start).Seconds()) {
		result, err := svc.DescribeInstances(instanceInput)

		if err != nil {
			fmt.Errorf("DescribeInstances Error: %v", err)
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
					if _, ok := myInstances.Load(*inst.PublicIpAddress); !ok {
						for _, t := range inst.Tags {
							if *t.Key == "Name" {
								myInstancesId.Store(*inst.InstanceId, *t.Value)
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
	myInstancesId.Range(func(k, v interface{}) bool {
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

	debugOutput(1, regions)

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
			go launchInstances(&rc, regions, OnDemand)
		}
	} else {
		for _, r := range launches.RegionInstances {
			if r.Number > 0 {
				wg.Add(1)
				go launchInstances(r, regions, OnDemand)
			}
			if r.Spot > 0 {
				wg.Add(1)
				go launchInstances(r, regions, Spot)
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
