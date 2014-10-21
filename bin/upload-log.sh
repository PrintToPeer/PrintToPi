#!/bin/bash
# Usage: upload-log.sh (uuid) (host)

UUID="$1"
HOST="$2"

LOGFILE="/var/PrintToPeer/logs/ptp_client.log"
LOGFILE_SNAPSHOT="`mktemp`.txt"

cp $LOGFILE $LOGFILE_SNAPSHOT
(curl -F uuid=$UUID -F log=@$LOGFILE_SNAPSHOT $HOST/logfiles; rm $LOGFILE_SNAPSHOT) &
