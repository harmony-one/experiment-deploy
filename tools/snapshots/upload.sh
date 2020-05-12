#!/bin/bash

for s in *.json; do
   aws s3 cp "${s}" s3://haochen-harmony-pub/pub/db_snapshot/"${s}" --acl public-read
done
