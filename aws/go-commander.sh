#!/bin/bash

IP=$(curl http://169.254.169.254/2018-03-28/meta-data/public-ipv4)

sudo ./commander -ip $IP
