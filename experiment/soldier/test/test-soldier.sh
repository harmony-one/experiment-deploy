#!/bin/bash

TEST=$1

baseurl=http://127.0.0.1:19000
cmds=( ping update init kill config )

declare -A testdata
testdata[update]=update.json
testdata[init]=init.json
testdata[config]=config.json

for cmd in "${cmds[@]}"; do
   if [ -n "$TEST" -a "$cmd" != "$TEST" ]; then
      continue
   fi

   if [ -f "${testdata[$cmd]}" ]; then
      echo curl -X GET $baseurl/$cmd --header "content-type: application/json" -d @${testdata[$cmd]}
      curl -X GET $baseurl/$cmd --header "content-type: application/json" -d @${testdata[$cmd]}
   else
      echo curl -X GET $baseurl/$cmd --header "content-type: application/json"
      curl -X GET $baseurl/$cmd --header "content-type: application/json"
   fi
done
