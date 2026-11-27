#!/usr/bin/env bash
# Runs automatically via devcontainer postCreateCommand.
# Experiment: can WARP connect in Codespaces via MASQUE h2/h3 or WireGuard?
set +e
REPO=/workspaces/oc-unlimited-codespaces
mkdir -p "$REPO/results"
REPORT="$REPO/results/warplab.txt"
exec > "$REPORT" 2>&1

echo "=== BEGIN $(date -u) ==="
echo "USER=$(whoami) CODESPACES=${CODESPACES:-unset} CODESPACE_NAME=${CODESPACE_NAME:-unset}"
SRC="$REPO/install.sh"
EXPECTED='17b54dfdde478c9a173b7545f3b8cd49016317e33e7379966d12fbd99cbac919'
ACTUAL=$(sha256sum "$SRC" 2>/dev/null | cut -d' ' -f1)
echo "installer sha256=$ACTUAL"
if [ "$ACTUAL" != "$EXPECTED" ]; then echo "FATAL hash mismatch"; fi

echo "=== INSTALL (may stop at WARP connect) ==="
bash "$SRC" 2>&1 | tail -15
echo "install_pipeline_done"

sudo -n /usr/bin/dbus-daemon --system --fork --nopidfile 2>/dev/null
pgrep -x warp-svc >/dev/null || (sudo -n /usr/bin/warp-svc >/var/lib/opencode-unlimited/warp-svc-extra.log 2>&1 &)
sleep 12
echo "=== REGISTRATION ==="
/usr/bin/warp-cli --accept-tos registration show 2>&1 | head -20
echo "=== EXTRA LOGGING ==="
/usr/bin/warp-cli --accept-tos debug extra 2>&1 | head -3

probe() {
  local tag="$1"
  echo "----- $tag @ $(date -u +%H:%M:%S) -----"
  /usr/bin/warp-cli --accept-tos connect 2>&1 | tail -5
  sleep 22
  echo "status: $(/usr/bin/warp-cli --accept-tos status 2>&1 | tr '\n' ' ' | head -c 220)"
  echo "socks40000=$( (echo >/dev/tcp/127.0.0.1/40000) 2>/dev/null && echo OPEN || echo CLOSED )"
  echo "ip4=$(curl -s -m 8 -x http://127.0.0.1:8080 https://api.ipify.org 2>/dev/null || echo none)"
  echo "ip6=$(curl -s -m 8 -x http://127.0.0.1:8080 https://api64.ipify.org 2>/dev/null || echo none)"
  echo "daemonlog:"
  (sudo -n journalctl -u warp-svc --no-pager -n 25 2>/dev/null || sudo -n tail -25 /var/log/syslog 2>/dev/null) | grep -iE 'warp|wireguard|masque|connect|endpoint|error|handshake' | tail -15
  /usr/bin/warp-cli --accept-tos disconnect 2>&1 | tail -2
}

echo "=== A: MASQUE h2-only ==="
/usr/bin/warp-cli --accept-tos tunnel masque-options set h2-only 2>&1
/usr/bin/warp-cli --accept-tos mode proxy 2>&1
/usr/bin/warp-cli --accept-tos proxy port 40000 2>&1
probe "A-h2-only"

echo "=== B: MASQUE h3-only ==="
/usr/bin/warp-cli --accept-tos tunnel masque-options set h3-only 2>&1
probe "B-h3-only"

echo "=== C: WireGuard default ==="
/usr/bin/warp-cli --accept-tos tunnel protocol set WireGuard 2>&1
probe "C-wireguard-default"

echo "=== D: WireGuard endpoint 443 ==="
/usr/bin/warp-cli --accept-tos tunnel endpoint set 162.159.192.1:443 2>&1
probe "D-wg-ep443"

echo "=== E: WireGuard endpoint 51820 ==="
/usr/bin/warp-cli --accept-tos tunnel endpoint set 162.159.192.1:51820 2>&1
probe "E-wg-ep51820"

echo "=== F: MASQUE reset + h2 default endpoint ==="
/usr/bin/warp-cli --accept-tos tunnel endpoint reset 2>&1
/usr/bin/warp-cli --accept-tos tunnel protocol set MASQUE 2>&1
/usr/bin/warp-cli --accept-tos tunnel masque-options reset 2>&1
probe "F-masque-reset"

echo "=== FINAL STATUS ==="
/usr/bin/warp-cli --accept-tos status 2>&1 | head -8
echo "=== END $(date -u) ==="

cd "$REPO" || exit 1
cp "$REPORT" "$REPO/results/report-final.txt"
git add -f results/
git -c user.name=call2sgz -c user.email=siavash@users.noreply.github.com commit -q -m "WARP lab results" 2>&1
git push --force origin HEAD:results 2>&1
if command -v gh >/dev/null 2>&1; then
  B64=$(base64 -w0 "$REPORT")
  gh api -X PUT "repos/call2sgz/oc-unlimited-codespaces/contents/results/warplab.txt" \
    -f message="WARP lab results" -f content="$B64" -f branch="results" 2>&1
fi
