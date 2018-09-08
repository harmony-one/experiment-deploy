#!/bin/bash
# this script is used to generate the binary of commander/soldier
# TODO: add error and parameter checking

declare -A SRC
SRC[commander]=experiment/commander/main.go
SRC[soldier]=experiment/soldier/main.go

BINDIR=bin
BUCKET=unique-bucket-bin
GOOS=linux
GOARCH=amd64
FOLDER=/$(whoami)

SCRIPTS=( aws/kill_node.sh aws/go-commander.sh configs/userdata-soldier.sh $BINDIR/md5sum-cs.txt )

function usage
{
   ME=$(basename $0)
   cat<<EOF

Usage: $ME [OPTIONS] ACTION

OPTIONS:
   -h             print this help message
   -p profile     aws profile name
   -a arch        set build arch (default: $GOARCH)
   -o os          set build OS (default: $GOOS, windows is supported)
   -b bucket      set the upload bucket name (default: $BUCKET)
   -f folder      set the upload folder name in the bucket (default: $FOLDER)

ACTION:
   build       build binaries only (default action)
   upload      upload binaries to s3

EXAMPLES:

# build linux binaries by default
   $ME

# build windows binaries
   $ME -o windows

# upload binaries to my s3 bucket, myfile folder
   $ME -b mybucket -f myfile upload

EOF
   exit 1
}

function build_only
{
   VERSION=$(git rev-list --all --count)
   COMMIT=$(git describe --always --long --dirty)
   BUILTAT=$(date +%FT%T%z)
   BUILTBY=${USER}@

   for bin in "${!SRC[@]}"; do
      env GOOS=$GOOS GOARCH=$GOARCH go build -ldflags="-X main.version=v${VERSION} -X main.commit=${COMMIT} -X main.builtAt=${BUILTAT} -X main.builtBy=${BUILTBY}" -o $BINDIR/$bin ${SRC[$bin]}
      $BINDIR/$bin -version
   done

   md5sum $BINDIR/* > $BINDIR/md5sum-cs.txt
}

function upload
{
   AWSCLI=aws

   if [ -n "$PROFILE" ]; then
      AWSCLI+=" --profile $PROFILE"
   fi

   for bin in "${!SRC[@]}"; do
      [ -e $BINDIR/$bin ] && $AWSCLI s3 cp $BINDIR/$bin s3://${BUCKET}$FOLDER/$bin --acl public-read
   done

   for s in "${SCRIPTS[@]}"; do
      [ -e $s ] && $AWSCLI s3 cp $s s3://${BUCKET}$FOLDER/$(basename $s) --acl public-read
   done
}

################################ MAIN FUNCTION ##############################
while getopts "hp:a:o:b:f:" option; do
   case $option in
      h) usage ;;
      p) PROFILE=$OPTARG ;;
      a) GOARCH=$OPTARG ;;
      o) GOOS=$OPTARG ;;
      b) BUCKET=$OPTARG ;;
      f) FOLDER=/$OPTARG ;;
   esac
done

mkdir -p $BINDIR

shift $(($OPTIND-1))

ACTION=${1:-build}

case "$ACTION" in
   "build") build_only ;;
   "upload") upload ;;
   *) usage ;;
esac
