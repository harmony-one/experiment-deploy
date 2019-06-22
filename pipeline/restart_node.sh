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

unset -v default_timeout default_step_retries default_cycle_retries
default_timeout=90
default_step_retries=2
default_cycle_retries=2

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

		arguments:
		ip		the IP address to upgrade
	ENDEND
}

unset -v timeout step_retries cycle_retries
unset -v OPTIND OPTARG opt
OPTIND=1
while getopts ":${common_getopts_spec}t:r:R:" opt
do
	! process_common_opts "${opt}" || continue
	case "${opt}" in
	'?') usage "unrecognized option -${OPTARG}";;
	':') usage "missing argument for -${OPTARG}";;
	t) timeout="${OPTARG}";;
	r) step_retries="${OPTARG}";;
	R) cycle_retries="${OPTARG}";;
	*) err 70 "unhandled option -${OPTARG}";;
	esac
done
shift $((${OPTIND} - 1))

: ${timeout="${default_timeout}"}
: ${step_retries="${default_step_retries}"}
: ${cycle_retries="${default_cycle_retries}"}

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

log_define -v restart_node_log_level -l DEBUG rn

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

unset -v logfile initfile

rn_info "looking for init file"
find_initfile() {
	local prefix
	for prefix in init leader.init
	do
		initfile="${logdir}/init/${prefix}-${ip}.json"
		[ -f "${initfile}" ] && return 0 || :
	done
	rn_crit "cannot find init file for ${ip}!"
	exit 78  # EX_CONFIG
}
find_initfile
rn_info "init file is ${initfile}"

rn_info "getting log filename"
get_logfile() {
	logfile=$("${progdir}/node_ssh.sh" -d "${logdir}" "${ip}" '
		ls -t ../tmp_log/log-*/*.log | head -1
	') || return $?
	if [ -z "${logfile}" ]
	then
		rn_warning "cannot find log file"
		return 1
	fi
}
run_with_retries get_logfile
rn_info "log file is ${logfile}"

kill_harmony() {
	local soldier_status status
	if soldier_status=$(curl -s "http://${ip}:19000/kill")
	then
		case "${soldier_status}" in
		Succeeded)
			rn_debug "kill succeeded"
			;;
		*)
			rn_info "soldier returned: $(shell_quote "${soldier_status}")"
			return 1
			;;
		esac
	else
		status=$?
		rn_warning "soldier curl returned status ${status}"
		return "${status}"
	fi
}

wait_for_harmony_process_to_exit() {
	local deadline now sleep status
	now=$(date +%s)
	deadline=$((${now} + 15))
	sleep=0
	while :
	do
		status=0
		"${progdir}/node_ssh.sh" -d "${logdir}" "${ip}" 'pgrep harmony > /dev/null' || status=$?
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

unset -v logsize
get_logfile_size() {
	logsize=$("${progdir}/node_ssh.sh" -d "${logdir}" "${ip}" 'stat -c %s '"$(shell_quote "${logfile}")") || return $?
	if [ -z "${logsize}" ]
	then
		rn_warning "cannot get size of log file ${logfile}"
		return 1
	fi
}

reinit_harmony() {
	local soldier_status status
	if soldier_status=$(curl -X GET -s "http://${ip}:19000/init" -H 'Content-Type: application/json' -d "@${initfile}")
	then
		case "${soldier_status}" in
		Succeeded)
			rn_debug "init succeeded"
			;;
		*)
			rn_info "soldier returned: $(shell_quote "${soldier_status}")"
			return 1;;
		esac
	else
		status=$?
		rn_warning "soldier_curl returned status ${status}"
		return "${status}"
	fi
}

wait_for_consensus() {
	local bingo now deadline
	now=$(date +%s)
	deadline=$((${now} + 90))
	while sleep 5
	do
		rn_debug "checking for bingo"
		bingo=$("${progdir}/node_ssh.sh" -d "${logdir}" "${ip}" '
			tail -c+'"$((${logsize} + 1)) $(shell_quote "${logfile}")"' |
			jq '\''select(.msg | test("HOORAY|BINGO"))'\'' | head -1
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

unset -v cycles_left cycle_ok
cycles_left=${cycle_retries}
while :
do
	while :
	do
		cycle_ok=false
		rn_info "killing harmony process"
		run_with_retries kill_harmony || break
		rn_info "waiting for harmony process to exit (if any)"
		run_with_retries wait_for_harmony_process_to_exit || break
		rn_info "getting logfile size"
		run_with_retries get_logfile_size || break
		rn_info "log file is ${logsize} bytes"
		rn_info "restarting harmony process"
		run_with_retries reinit_harmony || break
		rn_info "waiting for consensus to start"
		run_with_retries wait_for_consensus || break
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
