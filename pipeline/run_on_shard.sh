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
		usage: ${progname} [-t timestamp] [-qTOESrMpy] shard command

		options:
		-t timestamp	use the given timestamp (default: basename of realname of -d)
		-o outdir	use the given output directory
		 		(default: the run_on_shard/YYYY-MM-DDTHH:MM:SSZ subdir of -d)
		-q		quiet; do not summarize outputs
		-T		terse output; do not use BEGIN/END preamble for stdout/stderr
		 		(useful for one-liners)
		-O		do not print stdout
		-E		do not print stderr
		-S		do not print non-zero status
		-r		remove outdir (-o) after running
		-M		use opportunistic ssh connection multiplexing
		 		(helps back-to-back invocations); -M -M uses fresh mux
		-p		profile of network to run on (example: s3)
		-y		say yes to cmd confirmation

		shard		the shard number, such as 0
		command		the shell command to run on each host; may use \${ip}
		 		if given as @filename, use its contents
	ENDEND
}

unset -v ts outdir quiet terse remove print_stdout print_stderr print_status use_ssh_mux net_profile force_yes
quiet=false
terse=false
remove=false
print_stdout=true
print_stderr=true
print_status=true
use_ssh_mux=false
exit_mux_first=false
force_yes=false
net_profile=
unset -v OPTIND OPTARG opt
OPTIND=1
while getopts :t:o:qTOESrMp:y opt
do
	case "${opt}" in
	'?') usage "unrecognized option -${OPTARG}";;
	':') usage "missing argument for -${OPTARG}";;
	t) ts="${OPTARG}";;
	o) outdir="${OPTARG}";;
	q) quiet=true;;
	T) terse=true;;
	O) print_stdout=false;;
	E) print_stderr=false;;
	S) print_status=false;;
	r) remove=true;;
	M) exit_mux_first="${use_ssh_mux}"; use_ssh_mux=true;;
	p) net_profile="${OPTARG}";;
	y) force_yes=true;;
	*) err 70 "unhandled option -${OPTARG}";;
	esac
done
shift $((${OPTIND} - 1))

unset -v shard cmd
shard="${1-}"
shift 1 2> /dev/null || usage "missing shard argument"
cmd="${1-}"
shift 1 2> /dev/null || usage "missing command argument"
case $# in
[1-9]*)
	usage "extra arguments given"
	;;
esac

if [ -z "${net_profile}" ] ;then
	echo "profile not set, exiting..."
	exit
fi
logdir="logs/${net_profile}"
echo "profile: ${net_profile}"
echo "execute: ${cmd}"
if [ "${force_yes}" = false ] ;then
  printf "[Y]/n > "
  read -r yn
  if [ "${yn}" != "Y" ] ;then
     exit
  fi
fi

case "${ts+set}" in
'')
	unset -v real_logdir
	real_logdir=$(realpath "${logdir}")
	ts="${real_logdir##*/}"
	msg "using timestamp ${ts} (from ${logdir} -> ${real_logdir})"
	;;
esac
case "${ts}" in
[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].[0-9][0-9][0-9][0-9][0-9][0-9]) ;;
*) usage "timestamp ${ts} is not in YYYYMMDD.HHMMSS format";;
esac

case "${outdir+set}" in
'')
	mkdir -p "${logdir}/run_on_shard"
	outdir="$(mktemp -d "${logdir}/run_on_shard/$(date -u +%Y-%m-%dT%H:%M:%SZ).XXXXXX")"
	msg "using outdir ${outdir}"
	;;
esac

mkdir -p "${outdir}"
case "${cmd}" in
@*)
	cp "${cmd#@}" "${outdir}/cmd"
	;;
*)
	echo "${cmd}" > "${outdir}/cmd"
	;;
esac
cmd=$(cat "${outdir}/cmd")

unset -v shard_ip_file
shard_ip_file="${logdir}/shard${shard}.txt"

unset -v known_hosts_file
known_hosts_file="${logdir}/known_hosts_${shard}"
if [ ! -f "${known_hosts_file}" ]
then
	msg "collecting SSH host keys"
	ssh-keyscan -f "${shard_ip_file}" > "${known_hosts_file}"
fi
grep -v '^$' < "${shard_ip_file}" | (
	unset -v ip
	while read -r ip
	do (
		[ -n "${ip}" ] || exit 0
		set --
		if ${use_ssh_mux}
		then
			set -- "$@" -M
			if ${exit_mux_first}
			then
				set -- "$@" -M
			fi
		fi
		"${progdir}/node_ssh.sh" -d "${logdir}" -n "$@" "${ip}" '
			ts='\'"${ts}"\''
			ip='\'"${ip}"\''
			'"${cmd}"'
		' > "${outdir}/${ip}.out" 2> "${outdir}/${ip}.err" || echo $? > "${outdir}/${ip}.status"
		[ -s "${outdir}/${ip}.out" ] || rm -f "${outdir}/${ip}.out"
		[ -s "${outdir}/${ip}.err" ] || rm -f "${outdir}/${ip}.err"
	) & done
	wait
)

if ! ${quiet}
then
	(
		unset -v out err status
		while read -r ip
		do
			[ -n "${ip}" ] || continue
			out="${outdir}/${ip}.out"
			if ${print_stdout} && [ -f "${out}" ]
			then
				${terse} || echo "--- BEGIN ${ip} stdout ---"
				cat "${out}"
				${terse} || echo "--- END ${ip} stdout ---"
			fi
			err="${outdir}/${ip}.err"
			if ${print_stderr} && [ -f "${err}" ]
			then
				echo "--- BEGIN ${ip} stderr ---"
				cat "${err}"
				echo "--- END ${ip} stderr ---"
			fi >&2
			status="${outdir}/${ip}.status"
			if ${print_status} && [ -f "${status}" ]
			then
				echo "${ip} returned status $(cat ${status})"
			fi >&2
		done
	) < "${shard_ip_file}"
fi

if ${remove}
then
	msg "removing ${outdir}"
	rm -rf "${outdir}"
else
	msg "results are in ${outdir}"
fi
