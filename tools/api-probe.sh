#!/usr/bin/env bash
# GET-ONLY probe of the Orchestrator API. Performs no writes of any kind.
# Usage:  ORCH_TOKEN=orch_xxx bash tools/api-probe.sh
# Output: tools/api-dump.txt  (secrets redacted, arrays truncated)
set -uo pipefail

: "${ORCH_TOKEN:?Set ORCH_TOKEN=orch_... before running}"
BASE="${ORCH_BASE:-https://orchestrator.abesadze.digital/api}"
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/api-dump.txt"
: > "$OUT"

fetch() {
  local name="$1" path="$2"
  local resp code body
  resp=$(curl -sS -m 45 -w $'\n%{http_code}' \
    -H "Authorization: Bearer $ORCH_TOKEN" \
    -H 'Accept: application/json' \
    "$BASE$path" 2>&1)
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  printf '%s' "$body" | python3 "$DIR/redact.py" "$name" "$path" "$code" >> "$OUT"
  printf '  %-6s %s\n' "$code" "$path"
}

echo "Probing $BASE (GET only)..."

fetch auth_me            /auth/me
fetch settings           /settings
fetch users              /users
fetch tokens             /tokens
fetch audit              "/audit?limit=3"
fetch dashboard          /dashboard
fetch sites              /sites
fetch sites_tags         /sites/tags
fetch notifications      /notifications
fetch alerts             /alerts
fetch log_errors         /log-errors
fetch uptime             /uptime
fetch monitor_system     /monitor/system
fetch monitor_history    /monitor/history
fetch monitor_stats_hist /monitor/stats/history
fetch monitor_processes  /monitor/processes
fetch monitor_apm        /monitor/apm
fetch monitor_services   /monitor/services
fetch monitor_ssl        /monitor/ssl
fetch billing_overview   /billing/overview
fetch billing_enforce    /billing/enforcement
fetch billing_clients    /billing/clients
fetch billing_plans      /billing/plans
fetch billing_policy     /billing/default-policy
fetch billing_subs       /billing/subscriptions
fetch billing_invoices   /billing/invoices
fetch billing_overdue    /billing/invoices/overdue
fetch billing_profit     /billing/profitability
fetch servers            /servers
fetch server_status      /server/status
fetch server_droplets    /server/droplets
fetch server_sizes       /server/sizes
fetch server_actions     /server/actions
fetch server_snapshots   /server/snapshots
fetch server_backups     /server/backups
fetch server_firewalls   /server/firewalls
fetch system_info        /system/info
fetch ai_config          /ai/config
fetch digest             /digest
fetch telegram_me        /telegram/me
fetch tasks              /tasks
fetch notes              /notes
fetch calendar           /calendar/events
# Fleet monitoring (admin only) — read by the Mac app's popover.
fetch fleet_servers      /fleet/servers
fetch fleet_alerts_open  "/fleet/alerts?active=1&limit=20"
fetch fleet_alerts_all   "/fleet/alerts?limit=5"

# --- per-site endpoints, using the first site returned by /sites ---
SITE_ID=$(curl -sS -m 30 -H "Authorization: Bearer $ORCH_TOKEN" -H 'Accept: application/json' "$BASE/sites" \
  | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if isinstance(d, dict):
    for k in ("sites", "data", "items", "results"):
        if isinstance(d.get(k), list):
            d = d[k]; break
if isinstance(d, list) and d and isinstance(d[0], dict):
    print(d[0].get("id", ""))
')

if [ -n "${SITE_ID:-}" ]; then
  echo "First site id: $SITE_ID"
  echo "### SITE_ID used for per-site probes: $SITE_ID" >> "$OUT"
  S="/sites/$SITE_ID"
  fetch site_detail       "$S"
  fetch site_releases     "$S/releases"
  fetch site_deploy_pend  "$S/deploy/pending"
  fetch site_branches     "$S/branches"
  fetch site_heatmap      "$S/deployments/heatmap"
  fetch site_test_stats   "$S/test-stats"
  fetch site_nginx        "$S/config/nginx"
  fetch site_env          "$S/config/env"
  fetch site_env_versions "$S/config/env/versions"
  fetch site_php_versions "$S/php-versions"
  fetch site_phpfpm       "$S/phpfpm"
  fetch site_ssl          "$S/ssl"
  fetch site_backups      "$S/database/backups"
  fetch site_backup_sched "$S/database/backup-schedule"
  fetch site_backup_s3    "$S/database/backup/s3"
  fetch site_databases    "$S/databases"
  fetch site_artisan_cmds "$S/artisan/commands"
  fetch site_composer_inf "$S/composer/info"
  fetch site_maintenance  "$S/maintenance"
  fetch site_supervisor   "$S/supervisor"
  fetch site_super_status "$S/supervisor/status"
  fetch site_scheduler    "$S/scheduler"
  fetch site_cron         "$S/cron"
  fetch site_queue_stats  "$S/queue/stats"
  fetch site_failed_jobs  "$S/failed-jobs"
  fetch site_logs         "$S/logs"
  fetch site_security     "$S/security"
  fetch site_status_page  "$S/status-page"
  fetch site_files        "$S/files?path=/"
  fetch site_health_score "/monitor/health-score/$SITE_ID"
  fetch uptime_history    "/uptime/$SITE_ID/history"
  fetch uptime_sparkline  "/uptime/$SITE_ID/sparkline"
else
  echo "!! Could not determine a site id from /sites — per-site endpoints skipped."
fi

echo
echo "Done. Wrote $OUT"
echo "Secrets are redacted and arrays truncated, but please skim it before sharing."
