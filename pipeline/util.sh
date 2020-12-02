. "${progdir}/msg.sh"

while_preserving() {
	local name names ret type opt OPTIND
	OPTIND=1
	while getopts : opt
	do
		case "${opt}" in
		'?')
			msg "while_preserving: unrecognized option -$OPTARG" >&2
			return 64
			;;
		':')
			msg "while_preserving: missing argument for -$OPTARG" >&2
			return 64
			;;
		esac
	done
	shift $(($OPTIND - 1))
	names=""
	while :
	do
		case $(($# > 0)) in
		0)
			break
			;;
		esac
		name="${1}"
		shift 1
		case "${name}" in
		--)
			break
			;;
		[^A-Za-z_]*|*[^A-Za-z0-9_]*)
			echo "while_preserving: invalid name \"${name}\"" >&2
			return 64
			;;
		name|names|ret|type|*__type|*__value)
			echo "while_preserving: reserved name \"${name}\"" >&2
			return 64
			;;
		esac
		names="${names} ${name}"
	done
	for name in ${names}
	do
		eval "local ${name}__type ${name}__value"
		eval "type=\"\${${name}-x}\${${name}-y}\""
		case "${type}" in
		xy)
			eval "${name}__type=unset"
			;;
		*)
			eval "${name}__value=\"\${${name}}\""
			if printenv | grep -q "^${name}="
			then
				eval "${name}__type=exported"
			else
				eval "${name}__type=set"
			fi
			;;
		esac
	done
	ret=0
	"$@" || ret=$?
	for name in ${names}
	do
		eval "unset ${name}"
		eval "type=\"\${${name}__type}\""
		case "${type}" in
		set|exported)
			eval "${name}=\"\${${name}__value}\""
			;;
		esac
		case "${type}" in
		exported)
			eval "export ${name}"
			;;
		esac
	done
	return "${ret}"
}

unexport() {
	local opt name ret val
	while getopts : opt
	do
		case "${opt}" in
		'?')
			echo "unexport: unrecognized option -$OPTARG" >&2
			return 64
			;;
		':')
			echo "unexport: missing argument for -$OPTARG" >&2
			return 64
			;;
		esac
	done
	shift $(($OPTIND - 1))
	ret=0
	for name
	do
		case "${name}" in
		[^A-Za-z_]*|*[^A-Za-z0-9_]*)
			echo "unexport: invalid name \"${name}\"" >&2
			ret=$((${ret} + 1))
			continue
			;;
		opt|name|val|ret) # local names
			echo "unexport: reserved name \"${name}\"" >&2
			ret=$((${ret} + 1))
			continue
			;;
		esac
		eval "val=\"\${${name}}\""
		eval "unset ${name}"
		eval "${name}=\"\${val}\""
	done
}

is_set() {
	local is_set
	eval "is_set=\"\${$1-x}\${$1-y}\""
	case "${is_set}" in
	xy)
		return 1
		;;
	esac
	return 0
}

bool() {
	if "$@"
	then
		echo true
	else
		echo false
	fi
}

shell_quote() {
	local r sep
	sep=""
	for r
	do
		echo -n "${sep}'"
		sep=" "
		while :
		do
			# avoid ${r} from being interpreted as echo option
			case "${r}" in
			*"'"*)
				echo -n "X${r%%"'"*}'\\''" | sed 's/^X//'
				r="${r#*"'"}"
				;;
			*)
				echo -n "X${r}" | sed 's/^X//'
				break
				;;
			esac
		done
		echo -n "'"
	done
}

bre_escape() {
	case $# in
	0)
		sed 's:[.^[$*\]:\\&:g'
		;;
	*)
		echo "$*" | bre_escape
		;;
	esac
}

ere_escape() {
	case $# in
	0)
		sed 's:[.^[$()|*+?{\]:\\&:g'
		;;
	*)
		echo "$*" | ere_escape
		;;
	esac
}

# declare a map of region name
declare -A REGION_KEY
REGION_KEY['us-east-1']='virginia-key-benchmark.pem'
REGION_KEY['compute-1']='virginia-key-benchmark.pem'
REGION_KEY['us-east-2']='ohio-key-benchmark.pem'
REGION_KEY['us-west-1']='california-key-benchmark.pem'
REGION_KEY['us-west-2']='oregon-key-benchmark.pem'
REGION_KEY['ap-northeast-1']='tokyo-key-benchmark.pem'
REGION_KEY['ap-southeast-1']='singapore-key-benchmark.pem'
REGION_KEY['ap-southeast-2']='dummy.pem'
REGION_KEY['eu-central-1']='frankfurt-key-benchmark.pem'
REGION_KEY['eu-west-1']='ireland-key-benchmark.pem'
REGION_KEY['gcp']='harmony-node.pem'
REGION_KEY['do']='do-node.pem'

find_cloud_from_ip()
{
   local ipaddr="$1"
   whois=$(whois $ipaddr | grep -m1 Email)
   if echo $whois | grep -E 'apnic|digitalocean|ripe' &> /dev/null; then
      echo do
      return
   fi
   if echo $whois | grep microsoft &> /dev/null; then
      echo azure
      return
   fi
   if echo $whois | grep amazon &> /dev/null; then
      echo aws
      return
   fi
   if echo $whois | grep google &> /dev/null; then
      echo gcp
      return
   fi
}


find_cloud_from_host()
{
   local hostname1="$1"
   if [ -n "$hostname1" ]; then
		# quick hack
		if [ "$hostname1" = "3(NXDOMAIN)" ]; then 
			cloud=do 
		else 
			dns=$(echo "$hostname1" | awk -F\. ' { print $(NF-2) }' )
			case "$dns" in
			"amazonaws")
				cloud=aws ;;
			"googleusercontent")
				cloud=gcp ;;
			*)
				cloud=unknown ;;
			esac
		fi
      	echo $cloud
   else
      echo null
   fi
}

find_key_from_host()
{
   local hostname2="$1"
   if [ -n "$hostname2" ]; then
		# quick hack
		if [ "$hostname2" = "3(NXDOMAIN)" ]; then
			reg='do'
		else
			vendor=$(find_cloud_from_host $hostname2)
			case "$vendor" in
			"aws")
				reg=$(echo "$hostname2" | awk -F\. ' { print $2 }' ) ;;
			"gcp")
				reg='gcp' ;;
			*)
				echo "ERROR: unknown cloud provider"
				return
			esac
		fi
      case "$WHOAMI" in
         # keep it backward compatible
         "HARMONY"|"PS"|"LRTN")
            echo ${REGION_KEY[$reg]}
            ;;
         # all new network should use new testnet keypair
         *) echo "harmony-testnet.pem"
            ;;
      esac
   fi
}

find_key_from_ip()
{
   local ip="$1"
   if [ -n "$ip" ]; then
      hostname=$(host "$ip" | awk ' { print $NF } ')
      find_key_from_host $hostname
   fi
}
