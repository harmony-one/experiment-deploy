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
		usage: ${progname} shard [shard ...]

		shard		the shard number, such as 0
	ENDEND
}

unset -v OPTIND OPTARG opt
OPTIND=1
while getopts :h opt
do
	case "${opt}" in
	'?') usage "unrecognized option -${OPTARG}";;
	':') usage "missing argument for -${OPTARG}";;
	h) print_usage; exit 0;;
	*) err 70 "unhandled option -${OPTARG}";;
	esac
done
shift $((${OPTIND} - 1))

unset -v shard
for shard
do
	"${progdir}/run_on_shard.sh" -Mr "${shard}" 'curl -s http://localhost:19000/kill; echo'
done
