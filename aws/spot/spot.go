package main

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
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	WAIT_COUNT = 60
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
	whoami        = os.Getenv("WHOAMI")
	t             = time.Now()
	now           = fmt.Sprintf("%d-%02d-%02d_%02d_%02d_%02d", t.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second())
	configDir     = flag.String("config_dir", "../configs", "the directory of all the configuration files")
	launchProfile = flag.String("launch_profile", "launch-1k.json", "the profile name for instance launch")
	awsProfile    = flag.String("aws_profile", "aws.json", "the profile of the aws configuration")
	debug         = flag.Int("debug", 0, "enable debug output level")
	tag           = flag.String("tag", whoami, "a tag in instance name")

	userData = flag.String("user_data", "userdata.sh", "userdata file for instance launch")

	myInstances sync.Map

	wg sync.WaitGroup

	messages = make(chan string)
)

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
		input = ec2.RunInstancesInput{
			ImageId:          aws.String(amiId),
			InstanceType:     aws.String(i.Type),
			MinCount:         aws.Int64(int64(i.Number / 2)),
			MaxCount:         aws.Int64(int64(i.Number)),
			KeyName:          aws.String(reg.KeyPair),
			SecurityGroupIds: []*string{aws.String(reg.Vpc.Sg)},
			TagSpecifications: []*ec2.TagSpecification{
				{
					ResourceType: aws.String("instance"),
					Tags: []*ec2.Tag{
						{
							Key:   aws.String("Name"),
							Value: aws.String(fmt.Sprintf("%s-%s-%s-od", reg.Code, whoami, now)),
						},
					},
				},
			},
		}

	case Spot:
		input = ec2.RunInstancesInput{
			ImageId:      aws.String(amiId),
			InstanceType: aws.String(i.Type),

			InstanceMarketOptions: &ec2.InstanceMarketOptionsRequest{
				MarketType: aws.String("spot"),
				SpotOptions: &ec2.SpotMarketOptions{
					MaxPrice: aws.String(strconv.FormatFloat(getPrice(regs, i.Type), 'g', 10, 64)),
				},
			},

			MinCount:         aws.Int64(int64(i.Spot / 2)),
			MaxCount:         aws.Int64(int64(i.Spot)),
			KeyName:          aws.String(reg.KeyPair),
			SecurityGroupIds: []*string{aws.String(reg.Vpc.Sg)},
			TagSpecifications: []*ec2.TagSpecification{
				{
					ResourceType: aws.String("instance"),
					Tags: []*ec2.Tag{
						{
							Key:   aws.String("Name"),
							Value: aws.String(fmt.Sprintf("%s-%s-%s-spot", reg.Code, whoami, now)),
						},
					},
				},
			},
		}
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

	messages <- fmt.Sprintf("%v/%s: sleeping for %d seconds ...", reg.Name, instType, 30)
	time.Sleep(WAIT_COUNT * time.Second)

	num := 0
	for m := 0; m < WAIT_COUNT; m++ {
		result, err := svc.DescribeInstances(instanceInput)

		if err != nil {
			fmt.Errorf("DescribeInstances Error: %v", err)
			break
		}

		/*
			token := result.NextToken
			if *debug > 2 {
				fmt.Printf("describe instances next token: %v\n", token)
			}
		*/
		for _, r := range result.Reservations {
			for _, inst := range r.Instances {
				if *inst.PublicIpAddress != "" {
					if _, ok := myInstances.Load(*inst.PublicIpAddress); !ok {
						myInstances.Store(*inst.PublicIpAddress, *inst.PublicDnsName)
						num++
					}
				} else {
					time.Sleep(100 * time.Millisecond)
				}
			}
		}
	}

	debugOutput(2, myInstances)

	messages <- fmt.Sprintf("%v: %d %s instances (used %v)", reg.Name, num, instType, time.Since(start))
	return nil
}

func main() {
	flag.Parse()

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

	var userDataString string
	if data, err := ioutil.ReadFile(launches.UserData.File); err != nil {
		exitErrorf("Unable to read userdata file: %v", launches.UserData.File)
	} else {
		// encode userData
		userDataString = base64.StdEncoding.EncodeToString(data)
	}

	debugOutput(2, userDataString)

	start := time.Now()

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
	go func() {
		for i := range messages {
			fmt.Println(i)
		}
	}()
	wg.Wait()

	fmt.Println("Total Used: ", time.Since(start))
}
