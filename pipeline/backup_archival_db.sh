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

case $# in
0) usage "missing shard arg";;
esac

unset -v now backup_dir
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
backup_dir=$(mktemp -d "${logdir}/archival-db.${now}.XXXXXX")
mkdir -p "${backup_dir}"

unset -v shard
for shard
do
	"${progdir}/run_on_shard.sh" -d "${logdir}" -rEST "${shard}" 'pgrep -f -a is_archival | grep -qv pgrep && echo "${ip}"' | (
		unset -v ip
		while read -r ip
		do
			echo "rsyncing from ${ip}"
			rsync -azH -e "${progdir}/node_ssh.sh" --delete "${ip}:harmony_db_*" "${backup_dir}/s${shard}-${ip}/" &
		done
		wait
	)
done
msg "backup finished and can be found in: ${backup_dir}"
