#!/usr/bin/env bash
# Runs automatically via devcontainer postCreateCommand.
set +e
REPO=/workspaces/oc-unlimited-codespaces
mkdir -p "$REPO/results"
REPORT="$REPO/results/report.txt"
exec > "$REPORT" 2>&1

echo "=== BEGIN $(date -u) ==="
echo "USER=$(whoami) CODESPACES=${CODESPACES:-unset} CODESPACE_NAME=${CODESPACE_NAME:-unset}"
SRC="$REPO/install.sh"
EXPECTED='17b54dfdde478c9a173b7545f3b8cd49016317e33e7379966d12fbd99cbac919'
ACTUAL=$(sha256sum "$SRC" 2>/dev/null | cut -d' ' -f1)
echo "installer sha256=$ACTUAL"
if [ "$ACTUAL" != "$EXPECTED" ]; then echo "FATAL hash mismatch"; cp "$REPORT" "$REPO/results/report-final.txt"; cd "$REPO"; git add -f results/; git commit -q -m report; git push --force origin HEAD:results; exit 1; fi

echo "=== INSTALL (expected to fail at MASQUE connect) ==="
bash "$SRC" 2>&1 | tail -25
echo "install_pipeline_done"

echo "=== SWITCH WARP TO WIREGUARD ==="
sudo -n /usr/bin/dbus-daemon --system --fork --nopidfile 2>/dev/null
pgrep -x warp-svc >/dev/null || (sudo -n /usr/bin/warp-svc >/var/lib/opencode-unlimited/warp-svc-extra.log 2>&1 &)
sleep 10
/usr/bin/warp-cli --accept-tos status 2>&1 | head -4
echo "-- set protocol --"
/usr/bin/warp-cli --accept-tos tunnel protocol set WireGuard 2>&1
echo "protocol_set_exit=$?"
/usr/bin/warp-cli --accept-tos tunnel protocol get 2>&1
/usr/bin/warp-cli --accept-tos mode proxy 2>&1
/usr/bin/warp-cli --accept-tos proxy port 40000 2>&1
echo "-- connect --"
/usr/bin/warp-cli --accept-tos disconnect 2>&1 | head -3
/usr/bin/warp-cli --accept-tos connect 2>&1 | head -10
for i in $(seq 1 12); do
  st=$(/usr/bin/warp-cli --accept-tos status 2>&1 | head -1)
  echo "status[$i]=$st"
  echo "$st" | grep -q 'Connected' && break
  sleep 10
done
/usr/bin/warp-cli --accept-tos status 2>&1 | head -4
echo "socks40000=$( (echo >/dev/tcp/127.0.0.1/40000) 2>/dev/null && echo OPEN || echo CLOSED )"
echo "egress_ip=$(curl -s -m 15 -x http://127.0.0.1:8080 https://api.ipify.org 2>/dev/null || echo none)"
echo "egress_ipv6=$(curl -s -m 15 -x http://127.0.0.1:8080 https://api64.ipify.org 2>/dev/null || echo none)"

PROMPT='فقط این عدد را حساب کن و هیچ چیز دیگری ننویس: (19 × 21) + 7'
echo "=== START CONTROLLER ==="
/usr/bin/python3 /var/lib/opencode-unlimited/ouc.py start --portable 2>&1 | tail -5
/usr/local/bin/ouc status 2>&1 | head -20
echo "=== TEST THROUGH WARP (native wrapper) ==="
/usr/local/bin/opencode run -m opencode/big-pickle "$PROMPT" 2>&1 | tail -20
echo "warp_big_pickle_exit=$?"
echo "=== ROTATION TEST (ouc hop) ==="
/usr/local/bin/ouc hop 2>&1 | tail -10
/usr/bin/warp-cli --accept-tos status 2>&1 | head -3
echo "egress_ip_after_hop=$(curl -s -m 15 -x http://127.0.0.1:8080 https://api.ipify.org 2>/dev/null || echo none)"
echo "=== TEST AFTER HOP ==="
/usr/local/bin/opencode run -m opencode/big-pickle "$PROMPT" 2>&1 | tail -12
echo "after_hop_exit=$?"
echo "=== OUC DOCTOR ==="
/usr/local/bin/ouc doctor 2>&1 | head -25
echo "=== END $(date -u) ==="

cp "$REPORT" "$REPO/results/report-final.txt"
cd "$REPO" || exit 1
git add -f results/
git -c user.name=call2sgz -c user.email=siavash@users.noreply.github.com commit -q -m "Codespace WireGuard report" 2>&1
git push --force origin HEAD:results 2>&1
if command -v gh >/dev/null 2>&1; then
  B64=$(base64 -w0 "$REPORT")
  gh api -X PUT "repos/call2sgz/oc-unlimited-codespaces/contents/results/report-final.txt" \
    -f message="Codespace WireGuard report (gh)" -f content="$B64" -f branch="results" 2>&1
fi
