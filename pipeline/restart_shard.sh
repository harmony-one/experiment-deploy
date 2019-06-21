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
		usage: ${progname} ${common_usage} cmd shard [shard ...]

		${common_usage_desc}

		arguments:
		cmd		shell command to execute with log fed into stdin
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

backup_dir="${1}"
shift 1
shard="${backup_dir##*/s}"
shard="${shard%%-*}"

pause() {
	unset -v junk
	read -r -p 'Press Enter to continue . . .' junk
}

echo "Shard: ${shard}"
echo "Backup: ${backup_dir}"

echo "Checking backup directory size"
du -sh "${backup_dir}"
pause

echo "Restoring backup back onto nodes..."
sep=
for ip in `./run_on_shard.sh -d "${logdir}" -rT "${shard}" 'echo $ip'`
do
	echo -n "${sep}${ip}"
	sep=", "
	rsync -aqHz -e "${progdir}/node_ssh.sh -d ${logdir}" "$backup_dir" "$ip:" &
done
echo -n "..."
wait
echo
pause

echo "Killing shard ${shard}..."
./kill_shard.sh -d "${logdir}" "${shard}"
pause

echo "Making sure no nodes still run in shard ${shard}..."
./run_on_shard.sh -d "${logdir}" -rS "${shard}" 'pgrep -a harmony'
pause

echo "Moving staged database back into place..."
./run_on_shard.sh -d "${logdir}" -r "${shard}" 'set -eu; sudo rm -rf harmony_db_*; sudo mv '"${backup_dir##*/}"'/harmony_db_* .; rmdir '"${backup_dir##*/}"'; sudo chown -Rh 0:0 harmony_db_*; du -sh harmony_db_*'
pause

echo "Restarting shard ${shard}..."
./go.sh -p ek-test reinit `./run_on_shard.sh -d "${logdir}" -rT "${shard}" 'echo $ip'`

echo
echo "All done!"
