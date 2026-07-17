#!/usr/bin/env bash

# Controlled updater for the chome Proxmox cluster and its guests.
# Run without --apply for a read-only preflight. Mutating phases require --apply.

set -Eeuo pipefail
shopt -s inherit_errexit

readonly SCRIPT_VERSION="1.1.3"
readonly NODES=(pve1 pve2 pve3)
readonly BACKUP_ROOT="/mnt/pve/truenas-backups/dump"
readonly DEFAULT_BACKUP_MAX_AGE_HOURS=36
readonly SSH_OPTIONS=(-n -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4)
declare -Ar APP_MIN_MEMORY_MB=(
  [10116]=10240 # Frigate workload headroom
  [10201]=1024  # Cleanuparr
  [10205]=4096  # Seerr
  [10207]=1024  # Tautulli
  [10210]=2048  # FlareSolverr
  [10213]=2048  # qBittorrent
)

APPLY=false
PHASE="preflight"
REBOOT_HOSTS=false
UPDATE_FIRMWARE=false
SKIP_BACKUP_CHECK=false
BACKUP_MAX_AGE_HOURS="$DEFAULT_BACKUP_MAX_AGE_HOURS"
LOG_ROOT="/var/log/chome-datacenter-upgrade"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
CURRENT_NODE="$(hostname -s)"
CURRENT_NODE="${CURRENT_NODE%%.*}"
LOCK_FD=9

declare -a FAILURES=()
declare -a WARNINGS=()
declare -a SUCCESSES=()

usage() {
  cat <<'EOF'
Usage: datacenter-upgrade [options]

Read-only by default. Use --apply to make changes.

Options:
  --apply                       Perform updates instead of only reporting them.
  --phase PHASE                 preflight, guests, apps, firmware, hosts, or all.
  --reboot-hosts                Reboot hosts one at a time when required.
  --firmware                    Include supported LVFS firmware updates.
  --backup-max-age-hours HOURS  Maximum acceptable backup age (default: 36).
  --skip-backup-check           Bypass the backup-age safety gate.
  --log-root PATH               Log directory (default: /var/log/chome-datacenter-upgrade).
  -h, --help                    Show this help.

Recommended full run from pve2:
  datacenter-upgrade --apply --phase all --reboot-hosts --firmware
EOF
}

while (($#)); do
  case "$1" in
    --apply) APPLY=true ;;
    --phase) PHASE="${2:?missing phase}"; shift ;;
    --reboot-hosts) REBOOT_HOSTS=true ;;
    --firmware) UPDATE_FIRMWARE=true ;;
    --backup-max-age-hours) BACKUP_MAX_AGE_HOURS="${2:?missing hours}"; shift ;;
    --skip-backup-check) SKIP_BACKUP_CHECK=true ;;
    --log-root) LOG_ROOT="${2:?missing path}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$PHASE" in
  preflight|guests|apps|firmware|hosts|all) ;;
  *) printf 'Invalid phase: %s\n' "$PHASE" >&2; exit 2 ;;
esac

[[ "$BACKUP_MAX_AGE_HOURS" =~ ^[0-9]+$ ]] || {
  printf 'Backup age must be a whole number of hours.\n' >&2
  exit 2
}

if [[ $EUID -ne 0 ]]; then
  printf 'Run as root on a Proxmox node.\n' >&2
  exit 1
fi

node_known=false
for node in "${NODES[@]}"; do
  if [[ "$node" == "$CURRENT_NODE" ]]; then
    node_known=true
    break
  fi
done

if ! $node_known; then
  printf 'Run this script on pve1, pve2, or pve3. Current host: %s\n' "$CURRENT_NODE" >&2
  exit 1
fi

mkdir -p "$LOG_ROOT"
LOG_FILE="$LOG_ROOT/${RUN_ID}-${PHASE}.log"
SUMMARY_FILE="$LOG_ROOT/${RUN_ID}-${PHASE}.summary"
exec 9>"$LOG_ROOT/.lock"
flock -n "$LOCK_FD" || {
  printf 'Another datacenter upgrade is already running.\n' >&2
  exit 1
}
exec > >(tee -a "$LOG_FILE") 2>&1

timestamp() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }
log() { printf '%s [%s] %s\n' "$(timestamp)" "$1" "$2"; }
info() { log INFO "$*"; }
warn() { WARNINGS+=("$*"); log WARN "$*"; }
success() { SUCCESSES+=("$*"); log OK "$*"; }
failure() { FAILURES+=("$*"); log ERROR "$*"; }

quote_command() {
  local quoted
  printf -v quoted '%q ' "$@"
  printf '%s' "$quoted"
}

node_run() {
  local node="$1"
  shift
  if [[ "$node" == "$CURRENT_NODE" ]]; then
    "$@"
  else
    # The command is intentionally quoted locally before the remote shell receives it.
    # shellcheck disable=SC2029
    ssh "${SSH_OPTIONS[@]}" "root@$node" "$(quote_command "$@")"
  fi
}

node_capture() {
  node_run "$@"
}

cluster_resources() {
  node_capture pve1 pvesh get /cluster/resources --type vm --output-format json
}

resource_node() {
  local vmid="$1"
  cluster_resources | jq -er --argjson vmid "$vmid" '.[] | select(.vmid == $vmid) | .node' | head -n1
}

resource_status() {
  local vmid="$1"
  cluster_resources | jq -er --argjson vmid "$vmid" '.[] | select(.vmid == $vmid) | .status' | head -n1
}

ensure_cluster_quorum() {
  local expected quorate
  expected="$(node_capture pve1 pvecm status)" || return 1
  quorate="$(awk -F: '/^Quorate:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' <<<"$expected")"
  [[ "$quorate" == "Yes" ]]
}

wait_for_ssh() {
  local node="$1" timeout="${2:-900}" elapsed=0
  while ((elapsed < timeout)); do
    if ssh "${SSH_OPTIONS[@]}" "root@$node" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 10
    ((elapsed += 10))
  done
  return 1
}

wait_for_node_down() {
  local node="$1" timeout="${2:-180}" elapsed=0
  while ((elapsed < timeout)); do
    if ! ssh "${SSH_OPTIONS[@]}" "root@$node" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
    ((elapsed += 5))
  done
  return 1
}

assert_recent_backups() {
  $SKIP_BACKUP_CHECK && {
    warn "Backup age gate was explicitly skipped"
    return 0
  }

  local resources now cutoff vmid name latest age_hours missing=0
  resources="$(cluster_resources)" || return 1
  now="$(date +%s)"
  cutoff=$((now - BACKUP_MAX_AGE_HOURS * 3600))

  while IFS=$'\t' read -r vmid name; do
    latest="$(node_capture pve1 find "$BACKUP_ROOT" -maxdepth 1 -type f -name "vzdump-*-${vmid}-*" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 || true)"
    if [[ -z "$latest" ]]; then
      failure "No backup found for $vmid ($name)"
      missing=1
      continue
    fi
    latest="${latest%% *}"
    latest="${latest%.*}"
    age_hours=$(((now - latest) / 3600))
    if ((latest < cutoff)); then
      failure "Backup for $vmid ($name) is ${age_hours}h old; limit is ${BACKUP_MAX_AGE_HOURS}h"
      missing=1
    else
      info "Backup gate: $vmid ($name) is ${age_hours}h old"
    fi
  done < <(jq -r '.[] | select(.template != 1) | [.vmid, (.name // "unnamed")] | @tsv' <<<"$resources" | sort -n)

  ((missing == 0))
}

preflight_node() {
  local node="$1"
  info "Preflight: $node"
  node_run "$node" pveversion -v >/dev/null || return 1
  node_run "$node" test -d /etc/pve || return 1
  # Expansion is intentionally deferred to the selected Proxmox host.
  # shellcheck disable=SC2016
  node_run "$node" bash -lc 'test "$(df -P / | awk "NR==2 {print \$5}" | tr -d % )" -lt 90' || return 1
  if node_run "$node" bash -lc 'systemctl list-units --state=failed --no-legend --plain | grep -q .'; then
    node_run "$node" systemctl --failed --no-pager || true
    return 1
  fi
  node_run "$node" pvesm status --enabled 1 >/dev/null || return 1
  if [[ -n "$(node_run "$node" journalctl -k --since '-24 hours' --no-pager -g 'oom-kill|Out of memory' -q 2>/dev/null || true)" ]]; then
    warn "$node recorded an out-of-memory event in the last 24 hours"
  fi
  success "Preflight passed for $node"
}

preflight_lxcs() {
  local resources node vmid name status failed=0
  resources="$(cluster_resources)" || return 1

  while IFS=$'\t' read -r node vmid name status; do
    [[ "$status" == "running" ]] || continue
    if node_run "$node" pct exec "$vmid" -- bash -lc 'systemctl list-units --state=failed --no-legend --plain | grep -q .'; then
      warn "LXC $vmid ($name) has failed units before the upgrade"
      node_run "$node" pct exec "$vmid" -- systemctl --failed --no-pager || true
      failed=1
    fi
  done < <(jq -r '.[] | select(.type == "lxc" and .template != 1) | [.node, .vmid, (.name // "unnamed"), .status] | @tsv' <<<"$resources" | sort -k1,1 -k2,2n)

  ((failed == 0))
}

preflight_app_resources() {
  local resources node vmid name status minimum configured failed=0
  resources="$(cluster_resources)" || return 1

  while IFS=$'\t' read -r node vmid name status; do
    minimum="${APP_MIN_MEMORY_MB[$vmid]:-}"
    [[ -n "$minimum" ]] || continue
    configured="$(node_capture "$node" pct config "$vmid" | awk -F': ' '/^memory:/ {print $2; exit}')"
    if [[ ! "$configured" =~ ^[0-9]+$ ]] || ((configured < minimum)); then
      failure "LXC $vmid ($name) has ${configured:-unknown}MB RAM; its supported updater requires at least ${minimum}MB"
      failed=1
    else
      info "Application resource gate: $vmid ($name) has ${configured}MB RAM (minimum ${minimum}MB)"
    fi
  done < <(jq -r '.[] | select(.type == "lxc" and .template != 1) | [.node, .vmid, (.name // "unnamed"), .status] | @tsv' <<<"$resources" | sort -k1,1 -k2,2n)

  ((failed == 0))
}

preflight() {
  info "Datacenter upgrade $SCRIPT_VERSION; mode=$($APPLY && echo apply || echo report); phase=$PHASE"
  ensure_cluster_quorum || {
    failure "Cluster is not quorate"
    return 1
  }
  success "Cluster quorum is healthy"

  local node failed=0
  for node in "${NODES[@]}"; do
    if ! preflight_node "$node"; then
      failure "Preflight failed for $node"
      failed=1
    fi
  done

  preflight_lxcs || failed=1
  preflight_app_resources || failed=1
  assert_recent_backups || failed=1
  ((failed == 0))
}

lxc_os_update() {
  local node="$1" vmid="$2" name="$3" initial_status="$4"
  local apt_script reboot_required=false

  info "LXC $vmid ($name) on $node: operating system update"
  if [[ "$initial_status" != "running" ]]; then
    if ! $APPLY; then
      info "LXC $vmid is stopped; it would be started temporarily"
      return 0
    fi
    node_run "$node" pct start "$vmid" || return 1
    sleep 5
  fi

  if $APPLY; then
    apt_script=$(cat <<'EOF'
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8 LC_ALL=C.UTF-8
apt-get update
apt-get -o Dpkg::Options::=--force-confold -o APT::Get::Always-Include-Phased-Updates=true -y dist-upgrade
dpkg --audit
apt-get clean
EOF
)
  else
    apt_script=$(cat <<'EOF'
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8 LC_ALL=C.UTF-8
apt-get update -qq
apt-get -s -o APT::Get::Always-Include-Phased-Updates=true dist-upgrade | awk '/^[0-9]+ upgraded/ {print}'
EOF
)
  fi

  node_run "$node" pct exec "$vmid" -- bash -lc "$apt_script" || return 1

  if $APPLY && node_run "$node" pct exec "$vmid" -- test -e /var/run/reboot-required; then
    reboot_required=true
    info "LXC $vmid requires a restart"
    node_run "$node" pct reboot "$vmid" --timeout 180 || return 1
    sleep 10
  fi

  if $APPLY; then
    node_run "$node" pct exec "$vmid" -- systemctl is-system-running --wait >/dev/null || {
      node_run "$node" pct exec "$vmid" -- systemctl --failed --no-pager || true
      return 1
    }
    node_run "$node" pct exec "$vmid" -- bash -lc '! systemctl list-units --state=failed --no-legend --plain | grep -q .' || return 1
  fi

  if [[ "$initial_status" != "running" ]] && $APPLY; then
    node_run "$node" pct shutdown "$vmid" --timeout 120 || return 1
  fi

  success "LXC $vmid ($name) OS update completed; restarted=$reboot_required"
}

qga_exec() {
  local node="$1" vmid="$2" timeout="$3"
  shift 3
  local response
  response="$(node_run "$node" qm guest exec "$vmid" --timeout "$timeout" -- "$@")" || return 1
  jq -r '."err-data" // empty' <<<"$response" >&2
  jq -r '."out-data" // empty' <<<"$response"
  [[ "$(jq -r '.exitcode // 1' <<<"$response")" == "0" ]]
}

linux_vm_update() {
  local node="$1" vmid="$2" name="$3"
  local script
  info "QEMU $vmid ($name) on $node: Linux operating system update"
  if $APPLY; then
    script='set -Eeuo pipefail; export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8; apt-get update; apt-get -o Dpkg::Options::=--force-confold -o APT::Get::Always-Include-Phased-Updates=true -y dist-upgrade; dpkg --audit; apt-get clean'
  else
    script='set -Eeuo pipefail; export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8; apt-get update -qq; apt-get -s -o APT::Get::Always-Include-Phased-Updates=true dist-upgrade | awk '\''/^[0-9]+ upgraded/ {print}'\'''
  fi
  qga_exec "$node" "$vmid" 3600 bash -lc "$script" || return 1
  success "QEMU $vmid ($name) Linux update completed"
}

windows_update_script() {
  cat <<'POWERSHELL'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$apply = $env:CHOME_APPLY -eq '1'
$session = New-Object -ComObject Microsoft.Update.Session
$searcher = $session.CreateUpdateSearcher()
$search = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
$updates = New-Object -ComObject Microsoft.Update.UpdateColl
$titles = @()

for ($i = 0; $i -lt $search.Updates.Count; $i++) {
    $update = $search.Updates.Item($i)
    if (-not $update.EulaAccepted) { $update.AcceptEula() }
    [void]$updates.Add($update)
    $titles += $update.Title
}

$result = [ordered]@{
    Found = $updates.Count
    Installed = 0
    RebootRequired = $false
    Titles = $titles
}

if ($apply -and $updates.Count -gt 0) {
    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $updates
    $downloadResult = $downloader.Download()
    if ([int]$downloadResult.ResultCode -notin 2, 3) {
        throw "Windows Update download failed with result $([int]$downloadResult.ResultCode)"
    }
    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $updates
    $installResult = $installer.Install()
    if ([int]$installResult.ResultCode -notin 2, 3) {
        throw "Windows Update install failed with result $([int]$installResult.ResultCode)"
    }
    $result.Installed = $updates.Count
    $result.RebootRequired = [bool]$installResult.RebootRequired
}

[PSCustomObject]$result | ConvertTo-Json -Depth 4 -Compress
POWERSHELL
}

windows_vm_update() {
  local node="$1" vmid="$2" name="$3" ps encoded output env_value=0
  info "QEMU $vmid ($name) on $node: Windows Update"
  $APPLY && env_value=1
  ps="$(windows_update_script)"
  # $env is PowerShell syntax and must remain literal in Bash.
  # shellcheck disable=SC2016
  printf -v ps '$env:CHOME_APPLY = '\''%s'\''\n%s' "$env_value" "$ps"
  encoded="$(iconv -f UTF-8 -t UTF-16LE <<<"$ps" | base64 -w0)"
  output="$(qga_exec "$node" "$vmid" 10800 powershell.exe -NoProfile -NonInteractive -EncodedCommand "$encoded")" || return 1
  info "Windows result for $vmid: $output"
  if $APPLY && jq -e '.RebootRequired == true' >/dev/null 2>&1 <<<"$output"; then
    info "QEMU $vmid requires a Windows restart"
    node_run "$node" qm reboot "$vmid" --timeout 180 || return 1
    sleep 30
  fi
  success "QEMU $vmid ($name) Windows Update completed"
}

haos_update() {
  local node="$1" vmid="$2" response updates update_type slug
  info "QEMU $vmid (Home Assistant OS): Supervisor-managed update check"
  qga_exec "$node" "$vmid" 300 bash -lc 'ha refresh-updates --no-progress >/dev/null; ha available-updates --raw-json' >/tmp/chome-ha-updates.json || return 1
  updates="$(jq -c '.data.available_updates // []' /tmp/chome-ha-updates.json)"
  info "Home Assistant pending updates: $(jq 'length' <<<"$updates")"
  if $APPLY; then
    while IFS=$'\t' read -r update_type slug; do
      case "$update_type" in
        core) qga_exec "$node" "$vmid" 3600 ha core update --no-progress >/dev/null || return 1 ;;
        os) qga_exec "$node" "$vmid" 3600 ha os update --no-progress >/dev/null || return 1 ;;
        supervisor) qga_exec "$node" "$vmid" 3600 ha supervisor update --no-progress >/dev/null || return 1 ;;
        addon|app) qga_exec "$node" "$vmid" 3600 ha apps update "$slug" --no-progress >/dev/null || return 1 ;;
        *) warn "Unsupported Home Assistant update type '$update_type' for '$slug'" ;;
      esac
    done < <(jq -r '.[] | [(.update_type // .type // "unknown"), (.slug // .name // "")] | @tsv' <<<"$updates")
  fi
  success "Home Assistant OS update check completed"
}

upgrade_guests() {
  local resources failed=0 node vmid name status ostype agent
  resources="$(cluster_resources)" || return 1

  while IFS=$'\t' read -r node vmid name status; do
    if ! lxc_os_update "$node" "$vmid" "$name" "$status"; then
      failure "LXC $vmid ($name) OS update failed"
      failed=1
    fi
  done < <(jq -r '.[] | select(.type == "lxc" and .template != 1) | [.node, .vmid, (.name // "unnamed"), .status] | @tsv' <<<"$resources" | sort -k1,1 -k2,2n)

  while IFS=$'\t' read -r node vmid name status; do
    [[ "$status" == "running" ]] || {
      warn "QEMU $vmid ($name) is stopped; operating system update was not attempted"
      continue
    }
    if [[ "$vmid" == "10101" ]]; then
      haos_update "$node" "$vmid" || { failure "Home Assistant OS update failed"; failed=1; }
      continue
    fi
    ostype="$(node_capture "$node" qm config "$vmid" | awk -F': ' '/^ostype:/ {print $2}')"
    agent="$(node_capture "$node" qm config "$vmid" | awk -F': ' '/^agent:/ {print $2}')"
    if [[ "$agent" != 1* ]] || ! node_run "$node" qm guest cmd "$vmid" ping >/dev/null 2>&1; then
      warn "QEMU $vmid ($name) has no working guest agent; OS update requires manual handling"
      continue
    fi
    case "$ostype" in
      l26) linux_vm_update "$node" "$vmid" "$name" || { failure "Linux QEMU $vmid update failed"; failed=1; } ;;
      win*) windows_vm_update "$node" "$vmid" "$name" || { failure "Windows QEMU $vmid update failed"; failed=1; } ;;
      *) warn "QEMU $vmid ($name) has unsupported ostype '$ostype'" ;;
    esac
  done < <(jq -r '.[] | select(.type == "qemu" and .template != 1) | [.node, .vmid, (.name // "unnamed"), .status] | @tsv' <<<"$resources" | sort -k1,1 -k2,2n)

  ((failed == 0))
}

omada_update() {
  local node="$1" vmid="$2" script
  script=$(cat <<'EOF'
set -Eeuo pipefail
page_url='https://support.omadanetworks.com/us/product/omada-software-controller/?resourceType=download'
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
curl -fsSL --retry 4 --retry-all-errors -A 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Safari/537.36' "$page_url" -o "$tmpdir/page.html"
url="$(python3 - "$tmpdir/page.html" <<'PY'
import html, re, sys
text = html.unescape(open(sys.argv[1], encoding='utf-8').read()).replace('\\/', '/')
matches = re.findall(r'https://static\.tp-link\.com/[^"<> ]+Omada[^"<> ]+linux_x64\.deb', text, re.I)
if not matches:
    raise SystemExit('No Linux x64 Omada package found on the official page')
print(matches[0])
PY
)"
installed="$(dpkg-query -W -f='${Version}' omadac 2>/dev/null || echo 0)"
if [[ ${CHOME_APPLY:-0} != 1 ]]; then
    candidate="$(basename "$url" | sed -nE 's/.*_v([0-9.]+)_linux_x64\.deb/\1/p')"
    printf 'Omada installed=%s candidate=%s url=%s\n' "$installed" "${candidate:-unknown}" "$url"
    exit 0
fi
curl -fL --retry 4 --retry-all-errors "$url" -o "$tmpdir/omada.deb"
dpkg-deb --info "$tmpdir/omada.deb" >/dev/null
candidate="$(dpkg-deb -f "$tmpdir/omada.deb" Version)"
printf 'Omada installed=%s candidate=%s url=%s\n' "$installed" "$candidate" "$url"
if dpkg --compare-versions "$candidate" le "$installed"; then
    exit 0
fi
sha256sum "$tmpdir/omada.deb"
export DEBIAN_FRONTEND=noninteractive
dpkg -i "$tmpdir/omada.deb" || apt-get -f -y install
systemctl restart tpeap
for _ in $(seq 1 60); do
    if systemctl is-active --quiet tpeap && curl -kfsS --max-time 5 https://127.0.0.1:8043/ >/dev/null; then
        printf '%s\n' "$candidate" >/root/.omada
        exit 0
    fi
    sleep 5
done
systemctl status tpeap --no-pager
exit 1
EOF
)
  node_run "$node" pct exec "$vmid" -- env CHOME_APPLY="$($APPLY && echo 1 || echo 0)" bash -lc "$script" || return 1
  success "Omada application update completed"
}

nextcloud_update() {
  local node="$1" vmid="$2" script
  if $APPLY; then
    script=$(cat <<'EOF'
set -Eeuo pipefail
occ='sudo -u www-data php /var/www/nextcloud/occ'
$occ status
if ! $occ update:check | tee /tmp/nextcloud-update-check | grep -q 'Everything up to date'; then
    sudo -u www-data php /var/www/nextcloud/updater/updater.phar --no-interaction
    $occ upgrade
fi
$occ app:update --all
$occ maintenance:repair
$occ status
systemctl is-active --quiet apache2 mariadb redis-server
EOF
)
  else
    script="sudo -u www-data php /var/www/nextcloud/occ status; sudo -u www-data php /var/www/nextcloud/occ update:check; sudo -u www-data php /var/www/nextcloud/occ app:update --showonly"
  fi
  node_run "$node" pct exec "$vmid" -- bash -lc "$script" || return 1
  success "Nextcloud application update completed"
}

ollama_update() {
  local node="$1" vmid="$2" script
  script=$(cat <<'EOF'
set -Eeuo pipefail
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
curl -fsSL --retry 4 https://api.github.com/repos/ollama/ollama/releases/latest -o "$tmpdir/release.json"
read -r tag url digest < <(python3 - "$tmpdir/release.json" <<'PY'
import json, sys
release = json.load(open(sys.argv[1], encoding='utf-8'))
asset = next(asset for asset in release['assets'] if asset['name'] == 'install.sh')
print(release['tag_name'], asset['browser_download_url'], asset['digest'])
PY
)
version="${tag#v}"
current="$(ollama --version 2>/dev/null | awk '{print $NF}')"
printf 'Ollama installed=%s candidate=%s\n' "$current" "$version"
if dpkg --compare-versions "$version" le "$current"; then
    exit 0
fi
curl -fL --retry 4 --retry-all-errors "$url" -o "$tmpdir/install.sh"
echo "${digest#sha256:}  $tmpdir/install.sh" | sha256sum -c -
OLLAMA_VERSION="$version" sh "$tmpdir/install.sh"
systemctl restart ollama
for _ in $(seq 1 60); do
    curl -fsS --max-time 5 http://127.0.0.1:11434/api/version >/dev/null && exit 0
    sleep 2
done
systemctl status ollama --no-pager
exit 1
EOF
)
  if ! $APPLY; then
    node_run "$node" pct exec "$vmid" -- bash -lc "ollama --version; curl -fsSL https://api.github.com/repos/ollama/ollama/releases/latest | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"tag_name\"])'" || return 1
  else
    node_run "$node" pct exec "$vmid" -- bash -lc "$script" || return 1
  fi
  success "Ollama application update completed"
}

frigate_update() {
  local node="$1" vmid="$2"
  if $APPLY; then
    # Expansion is intentionally deferred to the Frigate container shell.
    # shellcheck disable=SC2016
    node_run "$node" pct exec "$vmid" -- bash -lc 'set -Eeuo pipefail; cd /opt/frigate; docker compose pull; docker compose up -d --remove-orphans; for _ in $(seq 1 90); do health=$(docker inspect frigate --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" 2>/dev/null || true); [[ "$health" == healthy ]] && break; sleep 5; done; [[ "$health" == healthy ]]; curl -fsS http://127.0.0.1:5000/api/version; docker inspect frigate --format "health={{.State.Health.Status}} oom={{.State.OOMKilled}} restarts={{.RestartCount}}"' || return 1
  else
    node_run "$node" pct exec "$vmid" -- bash -lc 'curl -fsS http://127.0.0.1:5000/api/version; docker inspect frigate --format "image={{.Config.Image}} health={{.State.Health.Status}} oom={{.State.OOMKilled}} restarts={{.RestartCount}}"' || return 1
  fi
  success "Frigate application update completed"
}

generic_app_update() {
  local node="$1" vmid="$2" name="$3"
  if ! node_run "$node" pct exec "$vmid" -- test -x /usr/bin/update; then
    info "LXC $vmid ($name) has no application updater; OS packages only"
    return 0
  fi
  if ! $APPLY; then
    info "LXC $vmid ($name) has a dedicated application updater"
    return 0
  fi
  node_run "$node" pct exec "$vmid" -- timeout --signal=TERM --kill-after=2m 2h /usr/bin/update || return 1
  node_run "$node" pct exec "$vmid" -- bash -lc '! systemctl list-units --state=failed --no-legend --plain | grep -q .' || return 1
  success "LXC $vmid ($name) application update completed"
}

upgrade_apps() {
  local resources failed=0 node vmid name status
  resources="$(cluster_resources)" || return 1
  while IFS=$'\t' read -r node vmid name status; do
    [[ "$status" == "running" ]] || {
      warn "LXC $vmid ($name) is stopped; application update skipped"
      continue
    }
    case "$vmid" in
      10100) omada_update "$node" "$vmid" || { failure "Omada update failed"; failed=1; } ;;
      10107) nextcloud_update "$node" "$vmid" || { failure "Nextcloud update failed"; failed=1; } ;;
      10115) ollama_update "$node" "$vmid" || { failure "Ollama update failed"; failed=1; } ;;
      10116) frigate_update "$node" "$vmid" || { failure "Frigate update failed"; failed=1; } ;;
      *) generic_app_update "$node" "$vmid" "$name" || { failure "Application update failed for LXC $vmid ($name)"; failed=1; } ;;
    esac
  done < <(jq -r '.[] | select(.type == "lxc" and .template != 1) | [.node, .vmid, (.name // "unnamed"), .status] | @tsv' <<<"$resources" | sort -k1,1 -k2,2n)
  ((failed == 0))
}

prepare_fwupd_secure_boot() {
  local node="$1" script
  script=$(cat <<'EOF'
set -Eeuo pipefail
command -v mokutil >/dev/null 2>&1 || exit 0
mokutil --sb-state 2>/dev/null | grep -q '^SecureBoot enabled' || exit 0
test -f /usr/lib/shim/shimx64.efi.signed || {
  echo 'Secure Boot is enabled but the signed shim package is unavailable' >&2
  exit 1
}

install_shim() {
  local esp="$1"
  install -d -m 0755 "$esp/EFI/debian"
  install -m 0644 /usr/lib/shim/shimx64.efi.signed "$esp/EFI/debian/shimx64.efi"
}

if [[ -s /etc/kernel/proxmox-boot-uuids ]]; then
  mount_dir="$(mktemp -d)"
  trap 'mountpoint -q "$mount_dir" && umount "$mount_dir"; rmdir "$mount_dir"' EXIT
  while read -r uuid; do
    [[ -n "$uuid" ]] || continue
    mount "/dev/disk/by-uuid/$uuid" "$mount_dir"
    install_shim "$mount_dir"
    sync
    umount "$mount_dir"
  done < /etc/kernel/proxmox-boot-uuids
elif mountpoint -q /boot/efi; then
  install_shim /boot/efi
  sync
else
  echo 'Secure Boot is enabled but no Proxmox EFI system partition was found' >&2
  exit 1
fi
EOF
)
  node_run "$node" bash -lc "$script"
}

stage_firmware() {
  local node count failed=0
  if ! $UPDATE_FIRMWARE; then
    info "Firmware phase not requested"
    return 0
  fi
  for node in "${NODES[@]}"; do
    if ! node_run "$node" command -v fwupdmgr >/dev/null 2>&1; then
      warn "$node has no fwupdmgr; firmware check skipped"
      continue
    fi
    node_run "$node" fwupdmgr refresh --force >/dev/null || { failure "Firmware metadata refresh failed on $node"; failed=1; continue; }
    count="$(node_run "$node" bash -lc 'fwupdmgr get-updates --json 2>/dev/null | jq "[.Devices[]? | .Releases[]?] | length"')" || { failure "Firmware query failed on $node"; failed=1; continue; }
    info "$node firmware updates available: $count"
    if $APPLY && ((count > 0)); then
      prepare_fwupd_secure_boot "$node" || { failure "Secure Boot firmware preparation failed on $node"; failed=1; continue; }
      node_run "$node" fwupdmgr update --no-reboot-check --assume-yes || { failure "Firmware staging failed on $node"; failed=1; continue; }
      success "Firmware staged on $node"
    fi
  done
  ((failed == 0))
}

host_package_update() {
  local node="$1" script
  info "Proxmox host $node: package update"
  if $APPLY; then
    script='set -Eeuo pipefail; export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8; apt-get update; apt-get -o Dpkg::Options::=--force-confold -o APT::Get::Always-Include-Phased-Updates=true -y dist-upgrade; dpkg --audit; apt-get clean; pveversion -v'
  else
    script='set -Eeuo pipefail; apt-get update -qq; apt-get -s -o APT::Get::Always-Include-Phased-Updates=true dist-upgrade | awk '\''/^[0-9]+ upgraded/ {print}'\''; pveversion | head -n1'
  fi
  node_run "$node" bash -lc "$script" || return 1
  node_run "$node" bash -lc '! systemctl list-units --state=failed --no-legend --plain | grep -q .' || return 1
  success "Proxmox host $node package update completed"
}

host_needs_reboot() {
  local node="$1"
  # Expansion is intentionally deferred to the selected Proxmox host.
  # shellcheck disable=SC2016
  node_run "$node" bash -lc 'test -e /var/run/reboot-required || { running=$(uname -r); newest=$(dpkg -l "proxmox-kernel-*-pve-signed" 2>/dev/null | awk '\''$1 == "ii" {name=$2; sub(/^proxmox-kernel-/, "", name); sub(/-signed$/, "", name); print name}'\'' | sort -V | tail -n1); test -n "$newest" && test "$running" != "$newest"; }'
}

reboot_remote_host() {
  local node="$1"
  info "Rebooting $node"
  node_run "$node" systemctl reboot || true
  # Hosts can spend several minutes stopping large VMs before firmware begins.
  wait_for_node_down "$node" 900 || { failure "$node did not go down for reboot"; return 1; }
  wait_for_ssh "$node" 1200 || { failure "$node did not return after reboot"; return 1; }
  sleep 20
  ensure_cluster_quorum || { failure "Cluster quorum unhealthy after $node reboot"; return 1; }
  node_run "$node" bash -lc '! systemctl list-units --state=failed --no-legend --plain | grep -q .' || { node_run "$node" systemctl --failed --no-pager || true; return 1; }
  success "$node rebooted and rejoined the cluster on kernel $(node_capture "$node" uname -r)"
}

upgrade_hosts() {
  local node failed=0
  for node in "${NODES[@]}"; do
    if ! host_package_update "$node"; then
      failure "Package update failed on $node"
      failed=1
    fi
  done
  ((failed == 0)) || return 1

  if ! $APPLY || ! $REBOOT_HOSTS; then
    for node in "${NODES[@]}"; do
      host_needs_reboot "$node" && warn "$node requires a reboot"
    done
    return 0
  fi

  # Reboot remote hosts first. The orchestrator schedules its own reboot last.
  for node in "${NODES[@]}"; do
    [[ "$node" == "$CURRENT_NODE" ]] && continue
    host_needs_reboot "$node" || { info "$node does not require a reboot"; continue; }
    reboot_remote_host "$node" || return 1
  done

  if host_needs_reboot "$CURRENT_NODE"; then
    warn "$CURRENT_NODE will reboot in 60 seconds; this run ends after scheduling it"
    systemd-run --unit="chome-upgrade-final-reboot-$RUN_ID" --on-active=60s /usr/bin/systemctl reboot
  else
    info "$CURRENT_NODE does not require a reboot"
  fi
}

write_summary() {
  {
    printf 'run_id=%s\n' "$RUN_ID"
    printf 'script_version=%s\n' "$SCRIPT_VERSION"
    printf 'mode=%s\n' "$($APPLY && echo apply || echo report)"
    printf 'phase=%s\n' "$PHASE"
    printf 'successes=%s\n' "${#SUCCESSES[@]}"
    printf 'warnings=%s\n' "${#WARNINGS[@]}"
    printf 'failures=%s\n' "${#FAILURES[@]}"
    printf '\nSUCCESSES\n'
    printf '%s\n' "${SUCCESSES[@]:-none}"
    printf '\nWARNINGS\n'
    printf '%s\n' "${WARNINGS[@]:-none}"
    printf '\nFAILURES\n'
    printf '%s\n' "${FAILURES[@]:-none}"
  } | tee "$SUMMARY_FILE"
}

run_phase() {
  local name="$1"
  shift
  info "Starting phase: $name"
  if "$@"; then
    success "Phase completed: $name"
  else
    failure "Phase failed: $name"
    return 1
  fi
}

main() {
  local failed=0
  case "$PHASE" in
    preflight) run_phase preflight preflight || failed=1 ;;
    guests)
      run_phase preflight preflight || exit 1
      run_phase guests upgrade_guests || failed=1
      ;;
    apps)
      run_phase preflight preflight || exit 1
      run_phase apps upgrade_apps || failed=1
      ;;
    firmware)
      run_phase preflight preflight || exit 1
      run_phase firmware stage_firmware || failed=1
      ;;
    hosts)
      run_phase preflight preflight || exit 1
      run_phase hosts upgrade_hosts || failed=1
      ;;
    all)
      run_phase preflight preflight || exit 1
      run_phase guests upgrade_guests || failed=1
      run_phase apps upgrade_apps || failed=1
      if $UPDATE_FIRMWARE; then run_phase firmware stage_firmware || failed=1; fi
      if ((failed == 0)); then
        run_phase hosts upgrade_hosts || failed=1
      else
        failure "Host update skipped because a guest or application phase failed"
      fi
      ;;
  esac
  write_summary
  ((failed == 0 && ${#FAILURES[@]} == 0))
}

main
