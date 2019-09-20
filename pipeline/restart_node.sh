#!/bin/sh

set -eu

unset -v progname progdir
progname="${0##*/}"
case "${0}" in
*/*) progdir="${0%/*}";;
*) progdir=".";;
esac

. "${progdir}/msg.sh"
. "${progdir}/usage.sh"
. "${progdir}/log.sh"
. "${progdir}/util.sh"
. "${progdir}/common_opts.sh"

unset -v default_timeout default_step_retries default_cycle_retries \
	default_bucket default_folder default_public_rpc
default_timeout=450
default_step_retries=2
default_cycle_retries=2
default_bucket=unique-bucket-bin
default_folder="${WHOAMI}"
default_public_rpc=true

print_usage() {
	cat <<- ENDEND
		usage: ${progname} ${common_usage} [-t timeout] [-r step_retries] [-R cycle_retries] ip

		Restarts the node at the given IP address.

		If a directory "staging" exists on the node host, ${progname}
		moves the node software in it into the nominal place after
		stopping and before starting.

		${progname} checks the node log after restarting and waits for
		the first BINGO or HOORAY message, with a timeout.

		${common_usage_desc}

		options:
		-t N		wait at most N seconds for BINGO/HOORAY (default: ${default_timeout})
		-r N		try a failed step N more times (default: ${default_step_retries})
		-R N		try a failed cycle N more times (default: ${default_cycle_retries})
		-U		upgrade the node software
		-B BUCKET	fetch upgrade binaries from the given bucket
		 		(default: ${default_bucket})
		-F FOLDER	fetch upgrade binaries from the given folder
		 		(default: ${default_folder})
		-P		disable public RPC

		arguments:
		ip		the IP address to upgrade
	ENDEND
}

unset -v timeout step_retries cycle_retries upgrade bucket folder
upgrade=false
unset -v OPTIND OPTARG opt
OPTIND=1
while getopts ":${common_getopts_spec}t:r:R:UB:F:P" opt
do
	! process_common_opts "${opt}" || continue
	case "${opt}" in
	'?') usage "unrecognized option -${OPTARG}";;
	':') usage "missing argument for -${OPTARG}";;
	t) timeout="${OPTARG}";;
	r) step_retries="${OPTARG}";;
	R) cycle_retries="${OPTARG}";;
	U) upgrade=true;;
	B) bucket="${OPTARG}";;
	F) folder="${OPTARG}";;
	P) public_rpc=false;;
	*) err 70 "unhandled option -${OPTARG}";;
	esac
done
shift $((${OPTIND} - 1))
default_common_opts

: ${timeout="${default_timeout}"}
: ${step_retries="${default_step_retries}"}
: ${cycle_retries="${default_cycle_retries}"}
: ${bucket="${default_bucket}"}
: ${folder="${default_folder}"}
: ${public_rpc="${default_public_rpc}"}

node_ssh() {
	"${progdir}/node_ssh.sh" -p "${profile}" -d "${logdir}" -o-n "$@"
}

case "${timeout}" in
""|*[^0-9]*) usage "invalid timeout: ${timeout}";;
esac
case "${step_retries}" in
""|*[^0-9]*) usage "invalid step retries: ${step_retries}";;
esac
case "${cycle_retries}" in
""|*[^0-9]*) usage "invalid cycle retries: ${cycle_retries}";;
esac

case $# in
0) usage "specify a node IP address to restart";;
esac
unset -v ip
ip="${1}"
shift 1

log_define -v restart_node_log_level -l INFO rn

# run_with_retries ${cmd} [${arg} ...]
#	Run the given command with the given arguments, if any, retrying the
#	command at most ${step_retries} times.
run_with_retries() {
	local retries_left status
	retries_left=${step_retries}
	while :
	do
		status=0
		"$@" || status=$?
		case "${status}" in
		0) return 0;;
		esac
		case $((${retries_left} > 0)) in
		0)
			rn_warning "retries exhausted"
			return ${status}
			;;
		esac
		rn_debug "${retries_left} retries left"
		retries_left=$((${retries_left} - 1))
	done
}

rn_notice "node to restart is ${ip}"

unset -v dns_zone
get_dns_zone() {
	rn_info "getting DNS zone with which to restart nodes"
	local rpczone
	rpczone=$(jq -r '.flow.rpczone // ""' < "${progdir}/../configs/benchmark-${profile}.json")
	case "${rpczone}" in
	?*) dns_zone="${rpczone}.hmny.io";;
	esac
	rn_info "DNS zone is ${dns_zone-'<unset>'}"
}

unset -v logfile zerologfile initfile is_explorer is_tf
find_initfile() {
	rn_info "looking for init file"
	local prefix
	is_explorer=false
	is_tf=false
	for prefix in init leader.init explorer.init
	do
		initfile="${logdir}/init/${prefix}-${ip}.json"
		if [ -f "${initfile}" ]
		then
			case "${initfile##*/}" in
			explorer.init-*) is_explorer=true;;
			esac
			rn_info "init file is ${initfile}"
			return 0
		fi
	done
	rn_info "cannot find init file for ${ip}; assuming a Terraform-provisioned node"
	is_tf=true
}

unset -v launch_args
get_launch_params() {
	if ${is_tf}
	then
		rn_info "proceeding without launch arguments (not applicable for Terraform-provisioned nodes)"
		return
	fi
	rn_info "getting launch arguments from init file"
	local port sid args rpc
	port="$(jq -r .port < "${initfile}")"
	sid="$(jq -r .sessionID < "${initfile}")"
	args="$(jq -r .benchmarkArgs < "${initfile}")"
	if ${public_rpc}
	then
		rpc="-public_rpc"
	fi
	set -- -ip "${ip}" -port "${port}" -log_folder "../tmp_log/log-${sid}" $rpc ${args}
	case "${dns_zone+set}" in
	set) set -- "$@" "-dns_zone=${dns_zone}";;
	esac
	launch_args=$(shell_quote "$@")
	rn_info "launch arguments are: ${launch_args}"
}

get_logfile() {
	rn_info "getting log filename"
	local logfiledir
	if ${is_tf}
	then
		logfiledir='latest'
	else
		logfiledir=$(node_ssh "${ip}" '
			ls -td ../tmp_log/log-* | head -1
		') || return $?
	fi
	if [ -z "${logfiledir}" ]
	then
		rn_warning "cannot find log directory"
		return 1
	fi
	logfile="${logfiledir}/validator-${ip}-9000.log"
	rn_info "log file is ${logfile}"
	zerologfile="${logfiledir}/zerolog-validator-${ip}-9000.log"
	rn_info "zerolog file is ${zerologfile}"
}

unset -v s3_folder
s3_folder="s3://${bucket}/${folder}"
rn_debug "s3_folder=$(shell_quote "${s3_folder}")"

fetch_binaries() {
	if ${is_tf}
	then
		# Terraform-provisioned nodes run node.sh which automatically
		# fetches latest binaries.
		return
	fi
	rn_info "fetching upgrade binaries"
	node_ssh "${ip}" "
		aws s3 sync $(shell_quote "${s3_folder}") staging
	"
}

kill_harmony() {
	rn_info "killing harmony process"
	local status
	status=0
	if ${is_tf}
	then
		node_ssh "${ip}" 'sudo systemctl stop harmony.service' || status=$?
	else
		node_ssh "${ip}" 'sudo pkill harmony' || status=$?
		case "${status}" in
		1) status=0;;  # it is OK if no processes have been found
		esac
	fi
	return ${status}
}

wait_for_harmony_process_to_exit() {
	rn_info "waiting for harmony process to exit (if any)"
	local deadline now sleep status
	now=$(date +%s)
	deadline=$((${now} + 15))
	sleep=0
	while :
	do
		status=0
		node_ssh "${ip}" 'pgrep harmony > /dev/null' || status=$?
		case "${status}" in
		0)
			;;
		1)
			break
			;;
		*)
			rn_warning "pgrep returned status ${status}"
			return ${status}
			;;
		esac
		now=$(date +%s)
		case $((${now} < ${deadline})) in
		0)
			rn_warning "harmony process won't exit!"
			return 1
			;;
		esac
		rn_debug "sleeping"
		sleep=$((${sleep} + 1))
		sleep ${sleep}
	done
}

upgrade_binaries() {
	rn_info "upgrading node software"
	if ${is_tf}
	then
		# Terraform-provisioned nodes run node.sh which automatically
		# upgrades to latest binaries.
		return
	fi
	node_ssh "${ip}" '
		set -eu
		unset -v f
		for f in harmony txgen wallet libmcl.so libbls384_256.so
		do
			rm -f "${f}"
			cp -p "staging/${f}" "${f}"
			case "${f}" in
			harmony|txgen|wallet)
				chmod a+x "${f}"
				;;
			esac
		done
	'
}

unset -v logsize zerologsize
_get_logfile_size() {
	rn_info "getting logfile size"
	local size file var
	file="${1}"
	var="${2}"
	size=$(node_ssh "${ip}" '
		unset -v logfile
		logfile='"$(shell_quote "${file}")"'
		[ -f "${logfile}" ] || sudo touch "${logfile}"
		stat -c %s ${logfile}
	') || return $?
	if [ -z "${size}" ]
	then
		rn_warning "cannot get size of log file ${file}"
		return 1
	fi
	rn_info "${file} is ${size} bytes"
	eval "${var}=\"\${size}\""
}

get_logfile_size() {
	_get_logfile_size "${logfile}" logsize
	_get_logfile_size "${zerologfile}" zerologsize
}

start_harmony() {
	rn_info "restarting harmony process"
	if ${is_tf}
	then
		node_ssh "${ip}" 'sudo systemctl start harmony.service'
	else
		node_ssh "${ip}" 'sudo sh -c '\''
			LD_LIBRARY_PATH=.
			export LD_LIBRARY_PATH
			exec < /dev/null > /dev/null 2>> harmony.err
			echo "running: ./harmony $*" >&2
			./harmony "$@" &
			echo "harmony is running, pid=$!" >&2
			echo $! > harmony.pid
		'\'' sh '"${launch_args}"
	fi
}

wait_for_consensus() {
	if ${is_explorer-false}
	then
		rn_info "${ip} is an explorer node; no need to wait for consensus"
		return
	fi
	rn_info "waiting for consensus to start"
	local bingo now deadline
	now=$(date +%s)
	deadline=$((${now} + ${timeout}))
	while sleep 5
	do
		rn_debug "checking for bingo"
		bingo=$(node_ssh "${ip}" '
			get_bingo() { # FILE SIZE MSGVAR
				local file size var
				file="${1}"
				size="${2}"
				var="${3}"
				tail -c"+${size}" "${file}" |
				jq -c '\''select(.'\''"${var}"'\'' | test("HOORAY|BINGO"))'\'' | head -1
			}
			get_bingo '"$(shell_quote "${logfile}" "${logsize}" msg)"'
			get_bingo '"$(shell_quote "${zerologfile}" "${zerologsize}" message)"'
		')
		case "${bingo}" in
		?*)
			rn_debug "bingo=$(shell_quote "${bingo}")"
			return 0
			;;
		esac
		now=$(date +%s)
		case $((${now} < ${deadline})) in
		0)
			break
			;;
		esac
	done
	rn_warning "consensus is not starting"
	return 1
}

# HERE BE DRAGONS

get_dns_zone
find_initfile
get_launch_params
run_with_retries get_logfile
unset -v cycles_left cycle_ok
cycles_left=${cycle_retries}
while :
do
	while :
	do
		cycle_ok=false
		if ${upgrade}
		then
			run_with_retries fetch_binaries || break
		fi
		run_with_retries kill_harmony || break
		run_with_retries wait_for_harmony_process_to_exit || break
		if ${upgrade}
		then
			run_with_retries upgrade_binaries || break
		fi
		run_with_retries get_logfile_size || break
		run_with_retries start_harmony || break
		wait_for_consensus || break
		break 2
	done
	case $((${cycles_left} > 0)) in
	0)
		rn_crit "cannot restart node, giving up!"
		exit 1
		;;
	esac
	rn_info "retrying restart cycle (${cycles_left} tries left)"
	cycles_left=$((${cycles_left} - 1))
done

rn_info "finished"
exit 0
