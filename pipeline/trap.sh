. "${progdir}/util.sh"
. "${progdir}/log.sh"

log_define -v TRAP_LOG_LEVEL trap

trap_body() {
	local func sig old_trap
	func="${1}"
	sig="${2}"
	shift 2
	trap_debug "trap_body: ${sig} caught, running ${func}" >&2
	"${func}"
	eval "old_trap=\"\${${func}_old_trap_${sig}-\"-\"}\""
	trap_debug "trap_body: old trap is $(shell_quote "${old_trap}")"
	case "${sig}" in
	EXIT)
		case "${old_trap}" in
		-)
			;;
		*)
			eval "${old_trap}"
			;;
		esac
		;;
	*)
		trap -- "${old_trap}" "${sig}"
		kill "-${sig}" $$
		;;
	esac
}

trap_save() {
	local func sig
	func="${1}"
	sig="${2}"
	shift 2
	eval "set -- $(trap -p "${sig}")"
	eval "${func}_old_trap_${sig}=\"\${3-\"-\"}\""
}

trap_setup() {
	local func sig
	func="${1}"
	shift 1
	trap_debug "setting up trap function ${func} for: $*"
	for sig
	do
		trap_save "${func}" "${sig}"
		trap "trap_body $(shell_quote "${func}" "${sig}")" "${sig}"
	done
}
