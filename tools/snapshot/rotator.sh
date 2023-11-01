#!/usr/bin/env bash

# `set -e``, while not perfect, catches and makes fatal many types of (otherwise silent) failure
# `set -u`` makes expansions of undefined variables fatal, which catches the classic case of rm -rf "${PERFIX}/usr/bin"
# `set -o pipefail` extends -e by making any failure anywhere in a pipeline fatal, rather than just the last command
set -eou pipefail

function installed {
    # Check that dependencies are installed
    cmd=$(command -v "${1}")

    [[ -n "${cmd}" ]] && [[ -f "${cmd}" ]]
    return ${?}
}

function log {
    # just enhanced logger with date
    echo "$(date -u '+%FT%T') - $*"
}
# export function for the `parallel` binary usage
export -f log

function die {
    # function to stop the script
    log >&2 "ERROR - $*"
    exit 1
}

function get_all_folders() {
    # get the whole list of the folders on the remote side
    # Inputs:
    # - $1 as array to store all folders
    # Outputs:
    # - $1 as array to store all folders as nameref
    local -n snaps=$1
    log "running - rclone lsf ${RCLONE_FULL_PATH}"
    snaps_str=$(rclone lsf "${RCLONE_FULL_PATH}")
    snaps_str=$(echo "${snaps_str}" | grep 'harmony_db_')
    readarray -t snaps <<<"${snaps_str}"
    log "there are ${#snaps[@]} snapshots"
}

function filter_old() {
    # filter old folders from the whole list by the TIME_LIMIT, convert it to linux time, make comparison,
    # add old to the removal list, print the list to delete in the logs
    # Inputs:
    # - $1 as array to store folders
    # - $2 as array with folders to delete
    # Outputs:
    # - $1 as array to store all folders as nameref
    # - $2 as array with folders to delete as nameref
    local -n full_list=$1
    local -n remove_list=$2
    # Get the current date minus TIME_LIMIT and convert to the Unix format
    TIME_LIMIT="$(date -u --date="${TIME_LIMIT} ago" '+%FT%T')"
    log "date to keep is starting at ${TIME_LIMIT}"
    TIME_LIMIT="$(date -u --date="${TIME_LIMIT}" +%s)"

    for file in "${full_list[@]}"; do
        # first cut is done to extract full date
        # second cut is removing time, we don't care about edge cases so much
        file_date=$(echo "${file}" | cut -d'.' -f 2 | cut -d'-' -f -3)
        file_date=$(date -d "${file_date}" +%s)
        if [[ "${TIME_LIMIT}" -ge "${file_date}" ]]; then
            remove_list+=("$file")
        fi
    done

    log "${#remove_list[@]} snapshots folders to delete:"
    (
        IFS=$'\n'
        echo "${remove_list[*]}"
    )
}

function remove_snaps() {
    # remove old snapshots in parallel, presume outputs in the right order.
    # GNU parallel will use as many jobs as N of CPU available
    # Inputs:
    # - $1 as array with folders to delete
    local -n remov_list=$1
    if ((${#remov_list[@]})); then
        parallel --keep-order --line-buffer \
            'log "started rclone delete" {}; rclone delete {}; log "finished rclone delete" {}' ::: "${remov_list[@]}"
    else
        log 'FINISHED - nothing to remove, all files are fresh'
    fi
}

# The list of input variables, if something isn't provided explicitly, use default value,
# if there is no default value -> just fail the whole script with empty var
REMOTE_PATH=${REMOTE_PATH:-""}
# var is an entry into `~/.config/rclone/rclone.conf`
RCLONE_CREDS=${RCLONE_CREDS:-"snapshot"}
S3_BUCKET=${S3_BUCKET:-""}
SHARD=${SHARD:-""}
TIME_LIMIT=${TIME_LIMIT:-"90 days"}

RCLONE_FULL_PATH="${RCLONE_CREDS}:${S3_BUCKET}/${REMOTE_PATH}/${SHARD}/"
# clean up all extra double slashes from input
RCLONE_FULL_PATH=${RCLONE_FULL_PATH//'//'/'/'}

# sanity checks
[[ "${BASH_VERSINFO[0]}" -lt 5 ]] && die "Bash >=5 required"

deps=(rclone parallel)
for dep in "${deps[@]}"; do
    installed "${dep}" || die "Missing '${dep}'"
done

declare -a snap_list=()
declare -a rem_list=()

get_all_folders snap_list
if ((${#snap_list[@]})); then
    filter_old snap_list rem_list
else
    log 'FINISHED - incoming folder empty/' \
        'file names do not match date YY-MM-DD format, please double check inputs'
    exit 0
fi

# append full path to every array element
rem_list=("${rem_list[@]/#/${RCLONE_FULL_PATH}}")

remove_snaps rem_list
