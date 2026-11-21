#!/bin/sh
set -e

collect_telemetry() {
  HOSTNAME_VAL=$(hostname 2>/dev/null || echo "unknown-host")
  KERNEL_VAL=$(uname -sr 2>/dev/null || echo "Linux")
  ARCH_VAL=$(uname -m 2>/dev/null || echo "x86_64")
  OS_NAME=$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || echo "Alpine Linux")
  NGINX_VER=$(nginx -v 2>&1 | sed 's/nginx version: //')

  # Detect container runtime markers
  RUNTIME_MODE="Host / Bare-Metal"
  if [ -f "/.dockerenv" ]; then
    RUNTIME_MODE="Docker Container (.dockerenv)"
  elif grep -qaE 'docker|containerd|kubepods|ecs' /proc/1/cgroup 2>/dev/null; then
    RUNTIME_MODE="OCI / Container Runtime"
  fi

  # Detect AWS EC2 / ECS / Cloud hints if present
  CLOUD_ENV="Local / Self-Hosted"
  if [ -n "$AWS_EXECUTION_ENV" ]; then
    CLOUD_ENV="AWS ($AWS_EXECUTION_ENV)"
  elif [ -n "$ECS_CONTAINER_METADATA_URI_V4" ]; then
    CLOUD_ENV="Amazon ECS / Fargate"
  elif grep -qi "amazon" /sys/devices/virtual/dmi/id/bios_version 2>/dev/null; then
    CLOUD_ENV="AWS EC2 Instance"
  fi

  # CPU model & cores
  CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || echo "")
  [ -z "$CPU_MODEL" ] && CPU_MODEL=$(uname -p 2>/dev/null || echo "Virtual CPU")
  CPU_CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "1")

  # Cgroup CPU quota (if container-limited)
  CPU_QUOTA="Unlimited (Host Shares)"
  if [ -f "/sys/fs/cgroup/cpu.max" ]; then
    Q_LINE=$(cat /sys/fs/cgroup/cpu.max)
    Q_MAX=$(echo "$Q_LINE" | awk '{print $1}')
    Q_PER=$(echo "$Q_LINE" | awk '{print $2}')
    if [ "$Q_MAX" != "max" ] && [ -n "$Q_PER" ] && [ "$Q_PER" -gt 0 ]; then
      CPU_QUOTA=$(awk "BEGIN {printf \"%.2f vCPU limit\", $Q_MAX / $Q_PER}")
    fi
  fi

  # Memory (Host /proc/meminfo & Cgroup limit)
  MEM_TOTAL_KB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo "0")
  MEM_AVAIL_KB=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo "0")
  MEM_TOTAL_MB=$((MEM_TOTAL_KB / 1024))
  MEM_AVAIL_MB=$((MEM_AVAIL_KB / 1024))
  MEM_USED_MB=$((MEM_TOTAL_MB - MEM_AVAIL_MB))

  CGROUP_MEM_LIMIT="Host Shared"
  if [ -f "/sys/fs/cgroup/memory.max" ]; then
    CG_RAW=$(cat /sys/fs/cgroup/memory.max)
    if [ "$CG_RAW" != "max" ] && [ "$CG_RAW" -gt 0 ] 2>/dev/null; then
      CGROUP_MEM_LIMIT="$((CG_RAW / 1024 / 1024)) MB"
    fi
  fi

  # Disk root usage
  DISK_INFO=$(df -Pm / 2>/dev/null | awk 'NR==2 {print $2" "$3" "$4" "$5}')
  DISK_TOTAL_MB=$(echo "$DISK_INFO" | awk '{print $1}')
  DISK_USED_MB=$(echo "$DISK_INFO" | awk '{print $2}')
  DISK_AVAIL_MB=$(echo "$DISK_INFO" | awk '{print $3}')
  DISK_PCT=$(echo "$DISK_INFO" | awk '{print $4}' | tr -d '%')

  # Load average & uptime
  LOAD_AVG=$(awk '{print $1", "$2", "$3}' /proc/loadavg 2>/dev/null || echo "0.00, 0.00, 0.00")
  UPTIME_SEC=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "0")

  # Container IP address
  CONTAINER_IP=$(hostname -i 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
  TIMESTAMP_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat <<EOF > /usr/share/nginx/html/telemetry.json.tmp
{
  "timestampUtc": "${TIMESTAMP_UTC}",
  "runtimeMode": "${RUNTIME_MODE}",
  "cloudEnvironment": "${CLOUD_ENV}",
  "hostname": "${HOSTNAME_VAL}",
  "containerIp": "${CONTAINER_IP}",
  "osPrettyName": "${OS_NAME}",
  "kernel": "${KERNEL_VAL}",
  "architecture": "${ARCH_VAL}",
  "webServer": "${NGINX_VER}",
  "cpu": {
    "model": "${CPU_MODEL}",
    "cores": ${CPU_CORES:-1},
    "cgroupQuota": "${CPU_QUOTA}",
    "loadAverage": "${LOAD_AVG}"
  },
  "memory": {
    "totalMb": ${MEM_TOTAL_MB:-0},
    "usedMb": ${MEM_USED_MB:-0},
    "availableMb": ${MEM_AVAIL_MB:-0},
    "cgroupLimit": "${CGROUP_MEM_LIMIT}"
  },
  "storage": {
    "totalMb": ${DISK_TOTAL_MB:-0},
    "usedMb": ${DISK_USED_MB:-0},
    "availableMb": ${DISK_AVAIL_MB:-0},
    "usedPercent": ${DISK_PCT:-0}
  },
  "uptimeSeconds": ${UPTIME_SEC:-0}
}
EOF
  mv /usr/share/nginx/html/telemetry.json.tmp /usr/share/nginx/html/telemetry.json
}

# Initial collection before nginx starts
collect_telemetry

# Background refresh loop every 5 seconds
(
  while true; do
    sleep 5
    collect_telemetry
  done
) &