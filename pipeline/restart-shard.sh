#!/bin/sh

set -eu

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
for ip in `./run_on_shard.sh -rT "${shard}" 'echo $ip'`
do
	echo -n "${sep}${ip}"
	sep=", "
	rsync -aqHz -e ./node_ssh.sh "$backup_dir" "$ip:" &
done
echo -n "..."
wait
echo
pause

echo "Killing shard ${shard}..."
./kill_shard.sh "${shard}"
pause

echo "Making sure no nodes still run in shard ${shard}..."
./run_on_shard.sh -rS "${shard}" 'pgrep -a harmony'
pause

echo "Moving staged database back into place..."
./run_on_shard.sh -r "${shard}" 'set -eu; sudo rm -rf harmony_db_*; sudo mv '"${backup_dir##*/}"'/harmony_db_* .; rmdir '"${backup_dir##*/}"'; sudo chown -Rh 0:0 harmony_db_*; du -sh harmony_db_*'
pause

echo "Restarting shard ${shard}..."
./go.sh -p drum reinit `./run_on_shard.sh -rT "${shard}" 'echo $ip'`

echo
echo "All done!"
