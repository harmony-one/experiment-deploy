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

print_usage() {
	cat <<- ENDEND
		usage: ${progname} ${common_usage} cmd shard [shard ...]

		options:

		cmd		shell command to execute with log fed into stdin
		shard		the shard number, such as 0
	ENDEND
}

unset -v OPTIND OPTARG opt
OPTIND=1
while getopts :hf opt
do
	case "${opt}" in
	'?') usage "unrecognized option -${OPTARG}";;
	':') usage "missing argument for -${OPTARG}";;
	h) print_usage; exit 0;;
	*) err 70 "unhandled option -${OPTARG}";;
	esac
done
shift $((${OPTIND} - 1))

case $# in
0) usage "missing shell command";;
esac

unset -v cmd
cmd="${1}"
shift 1

case $# in
0) usage "missing shard arg";;
esac

unset -v shard
for shard
do
	"${progdir}/run_on_shard.sh" -MTr "${shard}" 'cat ../tmp_log/log-"${ts}"/*-"${ip}"-9000.log | ('"${cmd:-"cat"}"')'
done
