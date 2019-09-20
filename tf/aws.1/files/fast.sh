#!/usr/bin/env bash

set -ex

# latested db snapshot as of Fri Sep 20 00:47:54 PDT 2019
DB[0]=harmony_db_0-836799.tar
DB[1]=harmony_db_1-807523.tar
DB[2]=harmony_db_2-820675.tar
DB[3]=harmony_db_3-802219.tar

# stop harmony service
sudo systemctl stop harmony.service

# download node2.sh file
curl -LO https://harmony.one/node2.sh
chmod +x node2.sh

unset shard

# determine the shard number
for s in 3 2 1; do
   if [ -d harmony_db_${s} ]; then
      shard=${s}
      # download shard db
      ./node2.sh -i ${shard} -b -a ${DB[${shard}]}
      break
   fi
done

# download beacon chain db anyway
./node2.sh -i 0 -b -a ${DB[0]}

# switch to new shard db
mv -f harmony_db_${shard} harmony_db_${shard}.bak
mv -f db/harmony_db_${shard} .
rm -f db/${DB[${shard}]}
rm -rf harmony_db_${shard}.bak

# switch to new beacon chain db
mv -f harmony_db_0 harmony_db_0.bak
mv -f db/harmony_db_0 .
rm -f db/${DB[0]}
rm -rf harmony_db_0.bak

# restart the harmony service
sudo systemctl start harmony.service
