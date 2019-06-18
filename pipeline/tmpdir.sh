. "${progdir}/trap.sh"

unset -v tmpdir
tmpdir=

tmpdir_cleanup() {
	case "${tmpdir}" in
	?*)
		rm -rf "${tmpdir}"
		tmpdir=
		;;
	esac
}

trap_setup tmpdir_cleanup EXIT HUP INT TERM

tmpdir=$(mktemp -d)
