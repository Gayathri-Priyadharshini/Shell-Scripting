
#!/bin/bash

# Linux Server Health Check Script
# Author: Gayathri Priyadharshini K
# Purpose: Monitor basic Linux server health

#To stop on undefined variable
set -u

DISK_THRESHOLD=80
REPORT_DIR="${REPORT_DIR:-./reports}"
 
mkdir -p "$REPORT_DIR" || exit 1

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
HOSTNAME=$(hostname)
REPORT_FILE="$REPORT_DIR/health_${HOSTNAME}_${TIMESTAMP}.log"

{
    echo "========================================"
    echo "       LINUX SERVER HEALTH REPORT"
    echo "========================================"

    echo "Hostname       : $HOSTNAME"
    echo "Date           : $(date)"
    echo "OS Information : $(grep '^PRETTY_NAME=' /etc/os-release | cut -d '"' -f 2)"
    echo "Kernel Version : $(uname -r)"

    echo ""
    echo "------------ UPTIME -------------------"
    uptime

    echo ""
    echo "------------ MEMORY -------------------"
    free -h

    echo ""
    echo "------------ CPU LOAD -----------------"
    uptime | awk -F'load average:' '{print $2}'

    echo ""
    echo "------------ DISK USAGE ---------------"
    df -hP -x tmpfs -x devtmpfs

    echo ""
    echo "------------ DISK ALERTS --------------"

    df -P -x tmpfs -x devtmpfs | awk -v threshold="$DISK_THRESHOLD" '
    NR > 1 {
        usage = $5
        gsub("%", "", usage)

        if (usage >= threshold) {
            print "WARNING: " $6 " is at " usage "% usage"
        }
    }'

    echo ""
    echo "------------ TOP PROCESSES ------------"
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 6

    echo ""
    echo "========================================"
    echo "       HEALTH CHECK COMPLETED"
    echo "========================================"

} | tee "$REPORT_FILE"

echo ""
echo "Report saved at: $REPORT_FILE"

