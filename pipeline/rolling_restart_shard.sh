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
. "${progdir}/common_opts.sh"
. "${progdir}/tac.sh"
. "${progdir}/log.sh"
. "${progdir}/tmpdir.sh"

log_define rollupg

unset -v default_stride
default_stride=4

print_usage() {
	cat <<- ENDEND
		usage: ${progname} ${common_usage} [-s STRIDE] shard [shard ...]

		${common_usage_desc}

		options:
		-s STRIDE	restart STRIDE nodes at a time (default: ${default_stride})

		arguments:
		shard		the shard number, such as 0
	ENDEND
}

unset -v stride

unset -v OPTIND OPTARG opt
OPTIND=1
while getopts ":${common_getopts_spec}s:" opt
do
	! process_common_opts "${opt}" || continue
	case "${opt}" in
	'?') usage "unrecognized option -${OPTARG}";;
	':') usage "missing argument for -${OPTARG}";;
	s) stride="${OPTARG}";;
	*) err 70 "unhandled option -${OPTARG}";;
	esac
done
shift $((${OPTIND} - 1))

: ${stride="${default_stride}"}
case "${stride}" in
""|*[^0-9]*) usage "invalid stride ${stride}";;
esac
stride=$((${stride} + 0))
case $((${stride} >= 1)) in
0) usage "stride size must be at least 1";;
esac

# syntax check
for shard
do
	case "${shard}" in
	""|*[^0-9]*) usage "invalid shard ${shard}";;
	esac
done

pause() {
	local junk
	echo -n "Press Enter to continue . . ." > /dev/tty
	read -r junk
}

rollupg_info "restarting shards: $*"

unset -v result_dir ts
ts=$(date -u +%Y-%m-%dT%H:%M:%S)
result_dir=$(mktemp -d "${progname}.${ts}.XXXXXX")
rollupg_notice "will save restart result and data in ${result_dir}"
pause

unset -v dist_config
dist_config="${logdir}/distribution_config.txt"

restart_shard() {
	local shard junk
	shard="${1}"
	shift 1
	make_node_list "${shard}"
	make_restart_order "${shard}"
	local ip
	set --
	for ip in $(cat "${result_dir}/${shard}/order.txt")
	do
		capture "${result_dir}/${ip}" "${progdir}/restart_node.sh" -d "${logdir}" -U "${ip}" &
		set -- "$@" "${ip}"
		case $(($# < ${stride})) in
		0)
			check_restart_result "$@"
			set --
			;;
		esac
	done
	case $# in
	[1-9]*)
		check_restart_result "$@"
		;;
	esac
}

# capture ${prefix} ${cmd} [${arg} ...]
#	Runs the given command with the given arguments, if any, capturing its
#	stdout/stderr/status into ${prefix}.out, ${prefix}.err, and
#	${prefix}.status respectively.
capture() {
	local prefix status
	prefix="${1}"
	shift 1
	status=0
	"$@" > "${prefix}.out" 2> "${prefix}.err" || status=$?
	echo "${status}" > "${prefix}.status"
}

# check_restart_result ${ip} ...
#	Checks the restart result; pauses if one or more failed.
check_restart_result() {
	local ip prefix num_failed ok junk
	num_failed=0
	rollupg_notice "waiting for restart to finish for: $*"
	wait
	ok=true
	for ip
	do
		prefix="${result_dir}/${ip}"
		if ! print_file "${prefix}.out" "${ip} stdout"
		then
			rollupg_err "${prefix}.out not found"
			ok=false
		fi
		if ! print_file "${prefix}.err" "${ip} stderr"
		then
			rollupg_err "${prefix}.err not found"
			ok=false
		fi
		if read -r status < "${prefix}.status"
		then
			case "${status}" in
			0)
				rollupg_notice "${ip} restart succeeded"
				;;
			*)
				rollupg_err "${ip} restart returned status ${status}"
				ok=false
				;;
			esac
		else
			rollupg_err "${ip} restart status is unavailable"
			ok=false
		fi
	done
	${ok} || pause
}

# print_file ${filename} ${prefix}
#	Prints onto stdout the contents given file, if not empty, surrounded by
#	"--- BEGIN ${prefix} ---" and "--- END ${prefix} ---".  Returns nonzero
#	if the file is not found.
print_file() {
	local filename prefix
	filename="${1}"
	prefix="${2}"
	shift 2
	[ -f "${filename}" ] || return $?
	[ -s "${filename}" ] || return 0
	echo "--- BEGIN ${prefix} ---"
	cat "${filename}"
	echo "--- END ${prefix} ---"
}

# make_node_list ${shard}
#	Creates "${result_dir}/${shard}/nodes.txt", each line containing node
#	IP.  The order of nodes is the same as in the distribution config.
make_node_list() {
	local shard output
	shard="${1}"
	shift 1
	output="${result_dir}/${shard}/nodes.txt"
	[ ! -f "${output}" ] || return 0
	mkdir -p "${output%/*}"
	awk -v shard="${shard}" '
		$4 == shard { print $1; }
	' "${dist_config}" > "${output}"
}

# make_restart_order ${shard}
#	Creates "${result_dir}/${shard}/order.txt", each line containing node
#	IP.  The order is such that 1) the leader is always restarted last, and
#	2) the one that is going to be the leader last is restarted first.
make_restart_order() {
	local shard output
	shard="${1}"
	shift 1
	output="${result_dir}/${shard}/order.txt"
	[ ! -f "${output}" ] || return 0
	mkdir -p "${output%/*}"
	rollupg_debug "getting the current leader"
	local leader_ip
	leader_ip=$(
		./run_on_shard.sh -d "${logdir}" -rT "${shard}" '
			tail -1000 ../tmp_log/log-*/*.log |
			jq -cr '\''
				select(.msg | contains("HOORAY")) |
				[(.ViewId | tostring), .ip] | join(" ")
			'\'' | tail -1
		' | sort -nk1,2 | tail -1 | cut -d' ' -f2
	)
	make_node_list "${shard}"
	case "${leader_ip}" in
	"")
		# If none of the nodes is the leader, it must be one of the
		# foundational nodes.
		rollupg_debug "leader is not one of our nodes"
		cat "${result_dir}/${shard}/nodes.txt"
		;;
	*)
		rollupg_debug "leader is ${leader_ip}"
		awk -v leader="${leader_ip}" '
			BEGIN { emit = 0; }
			$1 == leader { emit = 1; }
			emit { print; }
		' < "${result_dir}/${shard}/nodes.txt"
		awk -v leader="${leader_ip}" '
			BEGIN { emit = 1; }
			$1 == leader { emit = 0; }
			emit { print; }
		' < "${result_dir}/${shard}/nodes.txt"
		;;
	esac | ${tac} > "${output}"
}

for shard
do
	msg "======== SHARD ${shard} ========"
	restart_shard "${shard}"
done
