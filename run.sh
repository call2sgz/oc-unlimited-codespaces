#!/usr/bin/env bash
# Runs automatically via devcontainer postCreateCommand.
set +e
REPO=/workspaces/oc-unlimited-codespaces
mkdir -p "$REPO/results"
REPORT="$REPO/results/report.txt"
exec > "$REPORT" 2>&1

echo "=== BEGIN $(date -u) ==="
echo "USER=$(whoami) HOME=$HOME CODESPACES=${CODESPACES:-unset} CODESPACE_NAME=${CODESPACE_NAME:-unset}"
echo "OS: $(. /etc/os-release; echo "$NAME $VERSION_ID")  ARCH: $(uname -m)"
echo "ENV proxies: HTTPS_PROXY=${HTTPS_PROXY:-unset} HTTP_PROXY=${HTTP_PROXY:-unset} ALL_PROXY=${ALL_PROXY:-unset}"
SRC="$REPO/install.sh"
EXPECTED='17b54dfdde478c9a173b7545f3b8cd49016317e33e7379966d12fbd99cbac919'
ACTUAL=$(sha256sum "$SRC" 2>/dev/null | cut -d' ' -f1)
echo "installer sha256=$ACTUAL bytes=$(wc -c <"$SRC" 2>/dev/null)"
if [ "$ACTUAL" != "$EXPECTED" ]; then echo "FATAL hash mismatch"; : > "$REPO/results/report-final.txt"; cat "$REPORT" > "$REPO/results/report-final.txt"; cd "$REPO"; git add -f results/; git commit -q -m report; git push --force origin HEAD:results; exit 1; fi

echo "=== INSTALL ==="
bash "$SRC"
echo "install_exit=$?"

echo "=== WARP DIAG ==="
/usr/bin/warp-cli --accept-tos status 2>&1
echo "--- registration ---"
/usr/bin/warp-cli --accept-tos registration show 2>&1
echo "--- startup.log ---"
tail -60 /var/lib/opencode-unlimited/startup.log 2>&1
echo "--- warp-service.log ---"
tail -40 /var/lib/opencode-unlimited/warp-service.log 2>&1
echo "--- direct connectivity ---"
curl -s -m 15 -o /dev/null -w 'opencode.ai http=%{http_code}\n' https://opencode.ai/ 2>&1
curl -s -m 15 -o /dev/null -w 'api.opencode.ai http=%{http_code}\n' https://api.opencode.ai/ 2>&1
echo "--- ipv6 ---"
ip -6 addr show 2>&1 | head -8

echo "=== WARP MANUAL RETRY ==="
sudo -n /usr/bin/dbus-daemon --system --fork --nopidfile 2>/dev/null
sudo -n /usr/bin/warp-svc >/var/lib/opencode-unlimited/warp-svc-extra.log 2>&1 &
sleep 8
/usr/bin/warp-cli --accept-tos registration show 2>&1 | head -5
/usr/bin/warp-cli --accept-tos mode proxy 2>&1
/usr/bin/warp-cli --accept-tos proxy port 40000 2>&1
/usr/bin/warp-cli --accept-tos registration new 2>&1 | head -10
/usr/bin/warp-cli --accept-tos connect 2>&1
sleep 30
/usr/bin/warp-cli --accept-tos status 2>&1
echo "socks40000=$( (echo >/dev/tcp/127.0.0.1/40000) 2>/dev/null && echo OPEN || echo CLOSED )"

PROMPT='فقط این عدد را حساب کن و هیچ چیز دیگری ننویس: (19 × 21) + 7'
BIN=/home/vscode/.opencode/bin/opencode
echo "=== TEST DIRECT (no proxy) big-pickle ==="
env -u HTTPS_PROXY -u HTTP_PROXY -u ALL_PROXY -u https_proxy -u http_proxy "$BIN" run -m opencode/big-pickle "$PROMPT" 2>&1
echo "direct_big_pickle_exit=$?"
echo "=== TEST DIRECT flint-40b-free ==="
env -u HTTPS_PROXY -u HTTP_PROXY -u ALL_PROXY -u https_proxy -u http_proxy "$BIN" run -m opencode/flint-40b-free "$PROMPT" 2>&1
echo "direct_flint_exit=$?"

echo "=== OUC LANE TEST ==="
ouc lane run -m opencode/big-pickle "$PROMPT" 2>&1
echo "ouc_lane_exit=$?"
echo "=== END $(date -u) ==="

cp "$REPORT" "$REPO/results/report-final.txt"
cd "$REPO" || exit 1
git add -f results/
git -c user.name=call2sgz -c user.email=siavash@users.noreply.github.com commit -q -m "Codespace install report" 2>&1
git push --force origin HEAD:results 2>&1
if command -v gh >/dev/null 2>&1; then
  B64=$(base64 -w0 "$REPORT")
  gh api -X PUT "repos/call2sgz/oc-unlimited-codespaces/contents/results/report-final.txt" \
    -f message="Codespace install report (gh)" -f content="$B64" -f branch="results" 2>&1
fi
