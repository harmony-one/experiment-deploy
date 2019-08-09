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
. "${progdir}/util.sh"
. "${progdir}/log.sh"

log_define -v sync_logs_log_level -l DEBUG sl

: ${WHOAMI=`id -un`}
export WHOAMI

unset -v default_bucket default_profile default_owner
default_bucket=unique-bucket-bin
default_owner="${WHOAMI}"
default_profile="${WHOAMI}"

print_usage() {
	cat <<- ENDEND
		usage: ${progname} [-q] [-o owner] [-p profile] [-b bucket] [-f folder]

		options:
		-q		quick mode; do not download logs or databases
		-o owner	owner name (default: ${default_owner})
		-p profile	profile name (default: ${default_profile})
		-b bucket	bucket to configure into profile json (default: ${default_bucket})
		-f folder	folder to configure into profile json (default: same as owner)
	ENDEND
}

unset -v bucket folder profile owner quick
quick=false

unset -v OPTIND OPTARG opt
OPTIND=1
while getopts ":b:f:p:o:q" opt
do
	case "${opt}" in
	'?') usage "unrecognized option -${OPTARG}";;
	':') usage "missing argument for -${OPTARG}";;
	o) owner="${OPTARG}";;
	p) profile="${OPTARG}";;
	b) bucket="${OPTARG}";;
	f) folder="${OPTARG}";;
	q) quick=true;;
	*) err 70 "unhandled option -${OPTARG}";;
	esac
done
shift $((${OPTIND} - 1))

: ${owner="${default_owner}"}
: ${profile="${default_profile}"}
: ${bucket="${default_bucket}"}
: ${folder="${owner}"}

sl_info "fetching latest timestamp from S3 log folder"
unset -v latest_uri timestamp session_id
latest_uri="s3://harmony-benchmark/logs/latest-${owner}-${profile}.txt"
timestamp=$(aws s3 cp "${latest_uri}" -) || err 69 "cannot fetch latest timestamp"
sl_debug "timestamp=$(shell_quote "${timestamp}")"
session_id=$(echo "${timestamp}" | sed -n 's@^\([0-9][0-9][0-9][0-9]\)/\([0-9][0-9]\)/\([0-9][0-9]\)/\([0-9][0-9][0-9][0-9][0-9][0-9]\)$@\1\2\3.\4@p')
case "${session_id}" in
"") err 69 "cannot convert timestamp $(shell_quote "${timestamp}") into session ID; is it in YYYY/MM/DD/HHMMSS format?";;
esac

sl_info "syncing logs from S3"
if ${quick}
then
	set -- --exclude='*/tmp_log/*' --exclude='*/db-*.tgz'
else
	set --
fi
aws s3 sync "s3://harmony-benchmark/logs/${timestamp}" "${progdir}/logs/${session_id}" "$@"
sl_info "resetting log symlink"
rm -f "${progdir}/logs/${profile}"
ln -sf "${session_id}" "${progdir}/logs/${profile}"
sl_info "finished"
