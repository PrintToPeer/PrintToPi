#!/bin/bash

LOGFILE="$1"

LINES_WRITTEN=0
MAX_LINES=200

while read x; do
  echo "$x" >> $LOGFILE

  LINES_WRITTEN=$((LINES_WRITTEN+1))

  if [ $LINES_WRITTEN -gt $MAX_LINES ]; then
    tail -n $MAX_LINES $LOGFILE > $LOGFILE-1.log
    cat $LOGFILE-1.log > $LOGFILE
    rm $LOGFILE-1.log

    LINES_WRITTEN=0
  fi
done
