#!/bin/bash
if [ $# -ne 1 ]; then
  echo "Usage: $(basename $0) {arg}"
  exit -1
fi

for jarname in $( find . -type f -name *.jar ); do
  echo $jarname
  jar tvf $jarname | grep $1
done
