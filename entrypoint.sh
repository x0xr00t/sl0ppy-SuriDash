#!/bin/bash
# entrypoint.sh — routes to either the Suricata engine or the dashboard
set -eu

MODE="${1:-suridash}"
shift || true

case "$MODE" in
  suridash)
    # Interactive dashboard (compose run) — wait briefly for the sensor
    for i in $(seq 1 30); do
      [ -S "${SURICATA_SOCKET:-/run/suricata/suricata-command.socket}" ] && break
      sleep 1
    done
    exec /opt/suridash/suridash.sh "$@"
    ;;
  suricata)
    # Suricata engine — wait for rules to appear, then start in foreground
    if [ -d /var/lib/suricata/rules ] && [ -z "$(ls -A /var/lib/suricata/rules 2>/dev/null)" ]; then
      echo "[!] No rules found in /var/lib/suricata/rules — starting with no rule files." >&2
    fi
    exec /usr/bin/suricata \
        --unix-socket="${SURICATA_SOCKET:-/run/suricata/suricata-command.socket}" \
        -c /etc/suricata/suricata.yaml \
        "$@"
    ;;
  shell|bash)
    exec /bin/bash
    ;;
  *)
    echo "[-] Unknown mode: $MODE (use suricata | suridash | shell)" >&2
    exit 1
    ;;
esac
