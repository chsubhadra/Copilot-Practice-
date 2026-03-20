#!/usr/bin/env bash
# vm_health_check.sh - Check VM health (Ubuntu) based on CPU, Memory and Disk usage.
# Usage:
#   ./vm_health_check.sh [explain]
# Exit codes:
#   0 - Healthy (no resource > THRESHOLD)
#   1 - Not Healthy (one or more resources > THRESHOLD)
#   2 - Usage / error
set -euo pipefail

THRESHOLD=60

# Calculate CPU usage (%) over 1 second using /proc/stat
get_cpu_usage() {
  local line1 line2 arr1 arr2 total1 total2 idle1 idle2 totald idled cpu
  read -r line1 < /proc/stat
  read -ra arr1 <<< "$(awk '{for(i=2;i<=NF;i++) printf "%s ", $i}' <<<"$line1")"
  sleep 1
  read -r line2 < /proc/stat
  read -ra arr2 <<< "$(awk '{for(i=2;i<=NF;i++) printf "%s ", $i}' <<<"$line2")"

  total1=0; total2=0
  for v in "${arr1[@]}"; do total1=$((total1 + v)); done
  for v in "${arr2[@]}"; do total2=$((total2 + v)); done

  # idle = idle + iowait (indexes 3 and 4 after 'cpu')
  idle1=$(( ${arr1[3]:-0} + ${arr1[4]:-0} ))
  idle2=$(( ${arr2[3]:-0} + ${arr2[4]:-0} ))

  totald=$((total2 - total1))
  idled=$((idle2 - idle1))

  if [ "$totald" -le 0 ]; then
    cpu=0
  else
    cpu=$(( ( (totald - idled) * 100 ) / totald ))
  fi

  printf "%d" "$cpu"
}

# Calculate memory usage (%) using 'available' field: (total - available) / total * 100
get_mem_usage() {
  local total available used pct
  # Use bytes for precision; free prints a header line and Mem: line
  read -r total available < <(free -b | awk '/^Mem:/ {print $2, $7}')
  if [ -z "${total:-}" ] || [ "$total" -eq 0 ]; then
    pct=0
  else
    used=$(( total - available ))
    pct=$(( used * 100 / total ))
  fi
  printf "%d" "$pct"
}

# Get disk usage (%) for root filesystem '/'
get_disk_usage() {
  local p
  p=$(df -P / --output=pcent 2>/dev/null | tail -n1 | tr -dc '0-9')
  if [ -z "${p}" ]; then
    p=0
  fi
  printf "%d" "$p"
}

print_usage_and_exit() {
  echo "Usage: $0 [explain]"
  exit 2
}

main() {
  local explain=false
  if [ "${1:-}" = "explain" ]; then
    explain=true
  elif [ "${1:-}" = "" ]; then
    explain=false
  else
    print_usage_and_exit
  fi

  cpu_pct=$(get_cpu_usage)
  mem_pct=$(get_mem_usage)
  disk_pct=$(get_disk_usage)

  status="Healthy"
  reasons=()

  if [ "$cpu_pct" -gt "$THRESHOLD" ]; then
    status="Not Healthy"
    reasons+=("CPU usage: ${cpu_pct}% (> ${THRESHOLD}%)")
  fi
  if [ "$mem_pct" -gt "$THRESHOLD" ]; then
    status="Not Healthy"
    reasons+=("Memory usage: ${mem_pct}% (> ${THRESHOLD}%)")
  fi
  if [ "$disk_pct" -gt "$THRESHOLD" ]; then
    status="Not Healthy"
    reasons+=("Disk usage (/): ${disk_pct}% (> ${THRESHOLD}%)")
  fi

  echo "VM Health: $status"

  if [ "$explain" = true ]; then
    echo "Details:"
    printf "  CPU:    %s%%\n" "$cpu_pct"
    printf "  Memory: %s%%\n" "$mem_pct"
    printf "  Disk:   %s%%\n" "$disk_pct"
    if [ "${#reasons[@]}" -gt 0 ]; then
      echo "Reason(s):"
      for r in "${reasons[@]}"; do
        echo "  - $r"
      done
    else
      echo "All resource usages are at or below ${THRESHOLD}%."
    fi
  fi

  if [ "$status" = "Not Healthy" ]; then
    exit 1
  else
    exit 0
  fi
}

main "$@"