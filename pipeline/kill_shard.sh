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

print_usage() {
	cat <<- ENDEND
		usage: ${progname} ${common_usage} shard [shard ...]

		${common_usage_desc}

		arguments:
		shard		the shard number, such as 0
	ENDEND
}

unset -v OPTIND OPTARG opt
OPTIND=1
while getopts ":${common_getopts_spec}" opt
do
	! process_common_opts "${opt}" || continue
	case "${opt}" in
	'?') usage "unrecognized option -${OPTARG}";;
	':') usage "missing argument for -${OPTARG}";;
	*) err 70 "unhandled option -${OPTARG}";;
	esac
done
shift $((${OPTIND} - 1))
default_common_opts

unset -v shard
for shard
do
	"${progdir}/run_on_shard.sh" -d "${logdir}" -rT "${shard}" '
		if sudo pkill harmony
		then
			unset -v start end
			start=$(date +%s)
			while sudo pgrep harmony > /dev/null
			do
				sleep 1
			done
			end=$(date +%s)
			echo "${ip}: OK: $((${end} - ${start}))s"
		else
			echo "${ip}: ERROR: pkill returned $?"
		fi
	'
done
