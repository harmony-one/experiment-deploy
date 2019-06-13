. "${progdir}/msg.sh"

usage() {
	msg "$@"
	print_usage >&2
	exit 64  # EX_USAGE
}

print_usage() {
	: # to be defined by program
}
