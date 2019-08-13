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
		usage: ${progname} ${common_usage} shard ...

		${common_usage_desc}

		options:

		shard		the shard number, such as 0
	ENDEND
}

unset -v OPTIND OPTARG opt
OPTIND=1
while getopts :${common_getopts_spec} opt
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

case $# in
0) usage "missing shard argument";;
esac

unset -v shard
for shard
do
	jq < "raw-${shard}.txt" -c '.Peer' -r |
		sed -n 's/^.*BlsPubKey:\([[:xdigit:]]\{96\}\)-\([[:digit:]]\{1,3\}\.[[:digit:]]\{1,3\}\.[[:digit:]]\{1,3\}\.[[:digit:]]\{1,3\}\).*$/\2	\1/p' |
		sort -u \
		> "all-peers-${shard}.txt"
	sort "${logdir}/shard${shard}.txt" |
		join -v1 -t '	' "all-peers-${shard}.txt" - \
		> "ext-peers-${shard}.txt"
	cut < "ext-peers-${shard}.txt" -d '	' -f2 |
		sort -u \
		> "ext-keys-${shard}.txt"
	num_keys=$(($(wc -l < "ext-keys-${shard}.txt") + 0))
	echo ${shard} ${num_keys}
done
