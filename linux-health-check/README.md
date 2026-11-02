# linux-health-check

A single-file Bash script that gives a quick health summary of a Linux server: CPU, load, memory, swap, disk space, inodes and failed systemd services. It prints a plain-text report, can log or email it, and returns an exit code that monitoring tools or cron jobs can act on.

## Features

- CPU usage (sampled from `/proc/stat`, no extra packages)
- Load average, normalised per CPU core
- Memory and swap usage
- Disk space and inode usage for every real filesystem
- Failed systemd units (listed by name)
- Top 5 processes by CPU and memory
- `OK` / `WARN` / `CRIT` status per check, with configurable thresholds
- Exit codes: `0` OK, `1` WARN, `2` CRIT
- Optional log file (`-l`) and email on problems (`-m`)

## Requirements

- Bash 4+ (RHEL/CentOS 7+, Rocky/Alma, Amazon Linux, Ubuntu, Debian)
- Standard tools: `awk`, `df`, `ps`, `nproc`, `systemctl`
- `mail` (optional, only for the `-m` option)

## Usage

```bash
chmod +x health_check.sh
./health_check.sh                       # print report
./health_check.sh -l /var/log/health_check.log   # also append to a log file
./health_check.sh -m ops@example.com    # email the report if WARN or CRIT
./health_check.sh -h                    # help
```

### Custom thresholds

Thresholds are percentages (load is per core). Override them with environment variables:

```bash
DISK_WARN=75 DISK_CRIT=85 MEM_WARN=70 ./health_check.sh
```

| Variable | Default WARN | Default CRIT |
|---|---|---|
| `CPU_WARN` / `CPU_CRIT` | 70 | 90 |
| `MEM_WARN` / `MEM_CRIT` | 80 | 90 |
| `SWAP_WARN` / `SWAP_CRIT` | 50 | 80 |
| `DISK_WARN` / `DISK_CRIT` | 80 | 90 |
| `INODE_WARN` / `INODE_CRIT` | 80 | 90 |
| `LOAD_WARN` / `LOAD_CRIT` (per core) | 1.0 | 2.0 |
| `FAILED_WARN` / `FAILED_CRIT` (units) | 1 | 3 |

## Example output

```
=========== SERVER HEALTH REPORT: web01 ===========

--- CPU ---
CPU usage                  [OK]    12% used across 4 core(s)

--- MEMORY ---
Memory usage               [WARN]  83% used (6800000/8167000 kB, 1337 MB available)

--- DISK SPACE ---
/                          [OK]    47% used (8.6G/20G, 10G free) [/dev/xvda1, xfs]
/var                       [CRIT]  93% used (18G/20G, 1.4G free) [/dev/xvdb, xfs]

--- FAILED SERVICES ---
Failed units               [OK]    none

--- SUMMARY ---
OK: 12   WARN: 1   CRIT: 1
Overall status: CRITICAL
```

## Run it on a schedule (cron)

```cron
*/30 * * * * /opt/scripts/health_check.sh -l /var/log/health_check.log -m ops@example.com
```

## Use it with other tools

Because of the exit codes, it works as a simple check in CI jobs, Ansible tasks, or Nagios-style monitoring:

```bash
./health_check.sh > /dev/null || echo "Server needs attention"
```

## Lint

```bash
shellcheck health_check.sh
```

