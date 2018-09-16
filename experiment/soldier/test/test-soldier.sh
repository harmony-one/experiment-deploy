#!/usr/bin/env bash
#
# this script is used to test local soldier http server
# it sends REST api request to soldier

IP=127.0.0.1
PORT=9000

function usage
{
   ME=$(basename $0)
   cat<<EOT

$ME [OPTIONS] TEST

OPTIONS:
   -h             print this help message
   -p port        port of the soldier (default: $PORT)
   -i ip_address  IP address of the soldier (default: $IP)

TEST:
   upload         upload the distribution_config.txt to test bucket

   init,ping,kill,update,config
                  API test commands sent to the soldier
EOT
   exit 0
}

while getopts "p:hi:" option; do
   case $option in
      h) usage ;;
      p) PORT=$OPTARG ;;
      i) IP=$OPTARG ;;
   esac
done

shift $(($OPTIND-1))

TEST=$*

if [ -z "$TEST" ]; then
   usage
fi

baseurl=http://$IP:$PORT
cmds=( ping update init kill config )

declare -A testdata
testdata[update]=update.json
testdata[init]=init.json
testdata[config]=config.json

if [ "$TEST" == "upload" ]; then
   aws s3 cp distribution_config.txt s3://unique-bucket-bin/ec2-user/distribution_config.txt --acl public-read
   exit 0
fi

for cmd in "${cmds[@]}"; do
   if [ -n "$TEST" -a "$cmd" != "$TEST" ]; then
      continue
   fi

   if [ -f "${testdata[$cmd]}" ]; then
      echo curl -X GET $baseurl/$cmd --header "content-type: application/json" -d @${testdata[$cmd]}
      curl -X GET $baseurl/$cmd --header "content-type: application/json" -d @${testdata[$cmd]}
   else
      echo curl -X GET $baseurl/$cmd --header "content-type: application/json"
      curl -X GET $baseurl/$cmd --header "content-type: application/json"
   fi
done
