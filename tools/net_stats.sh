#!/bin/bash
# this script searches the leader/validator logs
# and trying to figure out the latency of block propagation
# the current block propagation is using a tree based gossip algorithm
# we will compare it with the IDA-raptorQ algorithm

# set -euo pipefail
# set -x
IFS=$'\n\t'

ME=`basename $0`

function usage
{
   cat<<EOF
Usage: $ME [Options] Command

OPTIONS:
   -h             print this help message
   -n             dry run mode
   -v             verbose mode
   -G             do the real job
   -D logdir      root directory of the log files (default: $DIRROOT)
   -S session     session ID (can be inferred from logdir, default: $SESSION)
   -p pattern     specify the pattern to use when searching leader log
                  this log is not needed for 'report' action

                  p1: default pattern ('NET: BLOCK PROPAGATION')
                  p2: legacy pattern ('"Size":3[3|4]')
                  p3: even older pattern ('')

COMMAND:
   extract        extract relevant logs from all log files
   report         analyze the logs and report latency

EXAMPLES:
   $ME -p p2 -D 20181109.215322 extract

   $ME -D 20181109.215322 report 

EOF
   exit 0
}

function logging
{
   echo $(date) : $@
   SECONDS=0
}

function _extract_logs
{
   CONFIG=$DIRROOT/distribution_config.txt
   NUM_SHARDS=$(grep leader $CONFIG | wc -l)
   NUM_SHARDS=$(( $NUM_SHARDS - 1 ))

   mkdir -p $LATDIR

   for s in $(seq 0 $NUM_SHARDS); do
      mkdir -p $LATDIR/shard$s
      grep "leader $s" $CONFIG | cut -f 1 -d' ' > $LATDIR/shard$s/leader.txt
      grep "validator $s" $CONFIG | cut -f 1 -d' ' > $LATDIR/shard$s/validators.txt
   done

   for s in $(seq 0 $NUM_SHARDS); do
      SHARD_TS_LOG=$LATDIR/shard$s
      logging "*** checking shard $s ***"
      readarray nodes < $LATDIR/shard$s/validators.txt

      leader=$(cat $LATDIR/shard$s/leader.txt)
      logging "leader: $leader"
      logging "pattern: $PATTERN"

      start_times=( $(grep -E "$PATTERN" $DIRROOT/leader/tmp_log/log-$SESSION/leader-$leader-*.log | grep -o '"t":".*Z"' | cut -b 5-) )

      rm -f $SHARD_TS_LOG/sent_*.log
      for st in $(seq 0 $(( ${#start_times[@]} - 1 )) ); do
         echo start_time_$st ${start_times[$st]} >> $SHARD_TS_LOG/sent_$st.log
      done

      rm -f $SHARD_TS_LOG/recv_*.log
      for node in ${nodes[@]}; do
         ls $DIRROOT/validator/tmp_log/log-$SESSION/validator-$node-*.log  > /dev/null
         if [ $? -eq 0 ]; then
            node_times=( $(grep 'Received Announce Message' $DIRROOT/validator/tmp_log/log-$SESSION/validator-$node-*.log | grep -o '"t":".*Z"' | cut -b 5-) )
            for nt in $(seq 0 $(( ${#node_times[@]} - 1 )) ); do
               echo "$node ${node_times[$nt]}" >> $SHARD_TS_LOG/recv_$nt.log
            done
         fi
      done
   done
}

function _report_stats
{
   CONFIG=$DIRROOT/distribution_config.txt
   NUM_SHARDS=$(grep leader $CONFIG | wc -l)
   NUM_SHARDS=$(( $NUM_SHARDS - 1 ))

   rm -f $LATDIR/block_lat.txt
   for s in $(seq 0 $NUM_SHARDS); do
      if [ -d $LATDIR/shard$s ]; then
         SHARD_TS_LOG=$LATDIR/shard$s
         rounds=$(ls $SHARD_TS_LOG/sent_*.log | wc -l)
         r=0
         while [ $r -lt $rounds ]; do
            sent_time=$(cat $SHARD_TS_LOG/sent_$r.log | cut -f2 -d' ' | tr -d \")
            recv_time=$(sort -k 2 $SHARD_TS_LOG/recv_$r.log | tail -n1 | cut -f2 -d' ' | tr -d \")
            sent_sec=$(date -d $sent_time +%s)
            sent_nsec=$(date -d $sent_time +%N)
            recv_sec=$(date -d $recv_time +%s)
            recv_nsec=$(date -d $recv_time +%N)

            diff_nsec=$( echo "($recv_sec - $sent_sec)*1000000000 + ($recv_nsec - $sent_nsec)" | bc)
            diff_sec=$( echo "$diff_nsec/1000000000" | bc)
            diff_nsec=$( echo "$diff_nsec%1000000000" | bc)

            printf "shard%s/round%s:%3d.%09ds\n" $s $r ${diff_sec} ${diff_nsec}
            printf "%d.%09d\n" ${diff_sec} ${diff_nsec} >> $LATDIR/block_lat.txt
            (( r++ ))
         done
      else
         logging missing shard directory: $LATDIR/shard$s
      fi
   done

   min=$(cat $LATDIR/block_lat.txt | jq -s min)
   max=$(cat $LATDIR/block_lat.txt | jq -s max)
   avg=$(cat $LATDIR/block_lat.txt | jq -s add/length)
   med=$(cat $LATDIR/block_lat.txt | sort -n|awk '{a[NR]=$0}END{print(NR%2==1)?a[int(NR/2)+1]:(a[NR/2]+a[NR/2+1])/2}')

   echo min:$min
   echo max:$max
   echo avg:$avg
   echo median:$med
}

########### MAIN ###########

DRYRUN=echo
DIRROOT=$(pwd)
SESSION=
TMPSESSION=
PAT=p1

declare -A PATTERNS
PATTERNS[p1]='START BLOCK PROPAGATION'
PATTERNS[p2]='"Size":3[3|4]'
PATTERNS[p3]=''

while getopts "hnvGD:S:p:" option; do
   case $option in
      n) DRYRUN=echo [DRYRUN] ;;
      v) VERBOSE=-v ;;
      G) DRYRUN= ;;
      D) DIRROOT=$OPTARG ;;
      S) TMPSESSION=$OPTARG ;;
      p) PAT=$OPTARG ;;
      h|?|*) usage ;;
   esac
done

LATDIR=$DIRROOT/latency

if [ -n "$TMPSESSION" ]; then
   SESSION=$TMPSESSION
else
   SESSION=$(basename $DIRROOT)
fi

PATTERN=${PATTERNS[$PAT]}

shift $(($OPTIND-1))

CMD="$@"

case $CMD in
   extract)
      _extract_logs
      ;;
   report)
      _report_stats
      ;;
   *)
      usage
      ;;
esac

exit 0

if [ ! -z $DRYRUN ]; then
   echo '***********************************'
   echo "Please use -G to do the real work"
   echo '***********************************'
fi
