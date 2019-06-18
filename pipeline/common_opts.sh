. "${progdir}/msg.sh"
. "${progdir}/usage.sh"

: ${WHOAMI=`id -un`}
export WHOAMI

unset -v default_logdir
default_logdir="${progdir}/logs/${WHOAMI}"

unset -v common_usage common_usage_desc
common_usage="[-h] [-d logdir]"
common_usage_desc="common options:
-d logdir	use the given logdir (default: ${default_logdir})
-h		print this help"

unset -v logdir
logdir="${default_logdir}"

unset -v common_getopts_spec
common_getopts_spec=hd:

process_common_opts() {
	case "${1-}" in
	d) logdir="${OPTARG}";;
	h) print_usage; exit 0;;
	*) return 1;;
	esac
}
