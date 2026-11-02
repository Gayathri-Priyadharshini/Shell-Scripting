#!/usr/bin/env bash
#
# health_check.sh - Linux server health check with a summary report
#
# Checks : CPU, memory, swap, disk space, inodes, load average, failed services
# Output : plain-text report on stdout (optionally appended to a log file / emailed)
# Exit   : 0 = all OK, 1 = at least one WARN, 2 = at least one CRIT
#
# Works on RHEL/CentOS 7+, Rocky/Alma, Amazon Linux, Ubuntu/Debian (bash 4+).
#
# Usage:
#   ./health_check.sh [-l LOGFILE] [-m EMAIL] [-h]
#
# Thresholds can be overridden with environment variables, e.g.:
#   DISK_WARN=75 DISK_CRIT=85 ./health_check.sh

set -uo pipefail   # no "-e": some checks intentionally return non-zero

VERSION="1.0.0"

# ----------------------------- thresholds (%) ---------------------------------
CPU_WARN=${CPU_WARN:-70};     CPU_CRIT=${CPU_CRIT:-90}
MEM_WARN=${MEM_WARN:-80};     MEM_CRIT=${MEM_CRIT:-90}
SWAP_WARN=${SWAP_WARN:-50};   SWAP_CRIT=${SWAP_CRIT:-80}
DISK_WARN=${DISK_WARN:-80};   DISK_CRIT=${DISK_CRIT:-90}
INODE_WARN=${INODE_WARN:-80}; INODE_CRIT=${INODE_CRIT:-90}
# Load average per CPU core (1.0 means every core is fully busy)
LOAD_WARN=${LOAD_WARN:-1.0};  LOAD_CRIT=${LOAD_CRIT:-2.0}
# Number of failed systemd units
FAILED_WARN=${FAILED_WARN:-1}; FAILED_CRIT=${FAILED_CRIT:-3}

# ------------------------------- options --------------------------------------
LOG_FILE=""
EMAIL_TO=""

# ------------------------------- state ----------------------------------------
OVERALL=0          # 0 OK, 1 WARN, 2 CRIT
COUNT_OK=0
COUNT_WARN=0
COUNT_CRIT=0
HOST=$(hostname -f 2>/dev/null || hostname)
REPORT_FILE=$(mktemp /tmp/health_check.XXXXXX)
trap 'rm -f "$REPORT_FILE"' EXIT

usage() {
  cat <<EOF
health_check.sh v${VERSION} - Linux server health check

Usage: $(basename "$0") [-l LOGFILE] [-m EMAIL] [-h]

  -l LOGFILE   append the report to LOGFILE
  -m EMAIL     email the report when status is WARN or CRIT (needs 'mail')
  -h           show this help

Override thresholds with environment variables:
  CPU_WARN CPU_CRIT MEM_WARN MEM_CRIT SWAP_WARN SWAP_CRIT
  DISK_WARN DISK_CRIT INODE_WARN INODE_CRIT LOAD_WARN LOAD_CRIT
  FAILED_WARN FAILED_CRIT

Exit codes: 0 = OK, 1 = WARN, 2 = CRIT
EOF
}

# ------------------------------- helpers --------------------------------------

# level_for VALUE WARN CRIT -> prints OK | WARN | CRIT (decimals supported)
level_for() {
  awk -v v="$1" -v w="$2" -v c="$3" \
    'BEGIN { if (v+0 >= c+0) print "CRIT"; else if (v+0 >= w+0) print "WARN"; else print "OK" }'
}

# record LEVEL -> update counters and the overall status
record() {
  case "$1" in
    CRIT) COUNT_CRIT=$((COUNT_CRIT + 1)); OVERALL=2 ;;
    WARN) COUNT_WARN=$((COUNT_WARN + 1)); [[ $OVERALL -lt 1 ]] && OVERALL=1 ;;
    OK)   COUNT_OK=$((COUNT_OK + 1)) ;;
  esac
}

section() { printf '\n--- %s ---\n' "$1"; }

# line LABEL LEVEL MESSAGE
line() { printf '%-26s %-7s %s\n' "$1" "[$2]" "$3"; }

# check LABEL VALUE WARN CRIT MESSAGE -> evaluate, record and print in one go
check() {
  local level
  level=$(level_for "$2" "$3" "$4")
  record "$level"
  line "$1" "$level" "$5"
}

meminfo() { awk -v k="$1" '$1 == k":" { print $2 }' /proc/meminfo; }

# ------------------------------- checks ---------------------------------------

show_system_info() {
  local os="unknown"
  if [[ -r /etc/os-release ]]; then
    os=$(. /etc/os-release && echo "${PRETTY_NAME:-$NAME}")
  fi
  section "SYSTEM"
  printf 'Hostname      : %s\n' "$HOST"
  printf 'OS            : %s\n' "$os"
  printf 'Kernel        : %s\n' "$(uname -r)"
  printf 'Uptime        : %s\n' "$(uptime -p 2>/dev/null || uptime)"
  printf 'Checked at    : %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
}

check_cpu() {
  section "CPU"
  local u1 n1 s1 i1 w1 q1 sq1 st1 u2 n2 s2 i2 w2 q2 sq2 st2
  local idle1 idle2 total1 total2 dt di usage cores

  # Sample /proc/stat twice, one second apart
  read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat
  sleep 1
  read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat

  idle1=$((i1 + w1));  idle2=$((i2 + w2))
  total1=$((u1 + n1 + s1 + i1 + w1 + q1 + sq1 + st1))
  total2=$((u2 + n2 + s2 + i2 + w2 + q2 + sq2 + st2))
  dt=$((total2 - total1))
  di=$((idle2 - idle1))

  if (( dt > 0 )); then
    usage=$(( (100 * (dt - di)) / dt ))
  else
    usage=0
  fi

  cores=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo)
  check "CPU usage" "$usage" "$CPU_WARN" "$CPU_CRIT" "${usage}% used across ${cores} core(s)"
}

check_load() {
  section "LOAD AVERAGE"
  local l1 l5 l15 cores per_core
  read -r l1 l5 l15 _ < /proc/loadavg
  cores=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo)
  per_core=$(awk -v l="$l1" -v c="$cores" 'BEGIN { printf "%.2f", l / c }')
  check "Load (1 min per core)" "$per_core" "$LOAD_WARN" "$LOAD_CRIT" \
    "1m=${l1} 5m=${l5} 15m=${l15} | ${cores} core(s) | ${per_core}/core"
}

check_memory() {
  section "MEMORY"
  local total avail used pct swap_total swap_free swap_used swap_pct

  total=$(meminfo MemTotal)
  avail=$(meminfo MemAvailable)
  # Very old kernels have no MemAvailable
  if [[ -z "$avail" ]]; then
    avail=$(( $(meminfo MemFree) + $(meminfo Buffers) + $(meminfo Cached) ))
  fi
  used=$((total - avail))
  pct=$(( (100 * used) / total ))
  check "Memory usage" "$pct" "$MEM_WARN" "$MEM_CRIT" \
    "${pct}% used (${used}/${total} kB, $((avail / 1024)) MB available)"

  swap_total=$(meminfo SwapTotal)
  swap_free=$(meminfo SwapFree)
  if (( swap_total > 0 )); then
    swap_used=$((swap_total - swap_free))
    swap_pct=$(( (100 * swap_used) / swap_total ))
    check "Swap usage" "$swap_pct" "$SWAP_WARN" "$SWAP_CRIT" \
      "${swap_pct}% used ($((swap_used / 1024))/$((swap_total / 1024)) MB)"
  else
    line "Swap usage" "OK" "no swap configured"
    record OK
  fi
}

check_disk() {
  section "DISK SPACE"
  local fs type size used avail pct mount

  while read -r fs type size used avail pct mount; do
    pct=${pct%\%}
    [[ "$pct" =~ ^[0-9]+$ ]] || continue
    check "$mount" "$pct" "$DISK_WARN" "$DISK_CRIT" \
      "${pct}% used (${used}/${size}, ${avail} free) [${fs}, ${type}]"
  done < <(df -PTh -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null | tail -n +2)
}

check_inodes() {
  section "INODES"
  local fs inodes iused ifree pct mount

  while read -r fs inodes iused ifree pct mount; do
    pct=${pct%\%}
    [[ "$pct" =~ ^[0-9]+$ ]] || continue     # some filesystems report "-"
    check "$mount" "$pct" "$INODE_WARN" "$INODE_CRIT" "${pct}% inodes used (${iused}/${inodes})"
  done < <(df -Pi -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null | tail -n +2)
}

check_services() {
  section "FAILED SERVICES"
  if ! command -v systemctl >/dev/null 2>&1; then
    line "systemd" "SKIP" "systemctl not available on this host"
    return
  fi

  local failed count
  failed=$(systemctl list-units --state=failed --no-legend --plain --no-pager 2>/dev/null | awk '{ print $1 }')
  count=$(printf '%s\n' "$failed" | grep -c .)

  if (( count == 0 )); then
    line "Failed units" "OK" "none"
    record OK
  else
    check "Failed units" "$count" "$FAILED_WARN" "$FAILED_CRIT" "${count} failed unit(s)"
    printf '%s\n' "$failed" | sed 's/^/    - /'
  fi
}

show_top_processes() {
  section "TOP 5 PROCESSES BY CPU"
  ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | head -n 6
  section "TOP 5 PROCESSES BY MEMORY"
  ps -eo pid,user,%cpu,%mem,comm --sort=-%mem 2>/dev/null | head -n 6
}

show_summary() {
  local status="OK"
  [[ $OVERALL -eq 1 ]] && status="WARNING"
  [[ $OVERALL -eq 2 ]] && status="CRITICAL"

  section "SUMMARY"
  printf 'OK: %d   WARN: %d   CRIT: %d\n' "$COUNT_OK" "$COUNT_WARN" "$COUNT_CRIT"
  printf 'Overall status: %s\n' "$status"
}

run_checks() {
  printf '=========== SERVER HEALTH REPORT: %s ===========\n' "$HOST"
  show_system_info
  check_cpu
  check_load
  check_memory
  check_disk
  check_inodes
  check_services
  show_top_processes
  show_summary
}

# --------------------------------- main ---------------------------------------

while getopts ":l:m:h" opt; do
  case "$opt" in
    l) LOG_FILE="$OPTARG" ;;
    m) EMAIL_TO="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage >&2; exit 3 ;;
    *) echo "Unknown option: -$OPTARG" >&2; usage >&2; exit 3 ;;
  esac
done

# Run in the current shell (no pipe) so counters/OVERALL are preserved
run_checks > "$REPORT_FILE"
cat "$REPORT_FILE"

if [[ -n "$LOG_FILE" ]]; then
  if mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null && cat "$REPORT_FILE" >> "$LOG_FILE" 2>/dev/null; then
    :
  else
    echo "Warning: could not write to log file $LOG_FILE" >&2
  fi
fi

if [[ -n "$EMAIL_TO" && $OVERALL -gt 0 ]]; then
  if command -v mail >/dev/null 2>&1; then
    subject="[$([[ $OVERALL -eq 2 ]] && echo CRITICAL || echo WARNING)] Health check on ${HOST}"
    mail -s "$subject" "$EMAIL_TO" < "$REPORT_FILE"
  else
    echo "Warning: 'mail' command not found, skipping email" >&2
  fi
fi

exit "$OVERALL"
