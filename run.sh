#!/usr/bin/env bash
# Runs automatically via devcontainer postCreateCommand.
# Installs the Codespaces-only unlimited-opencode bundle from the copy committed
# in this repo (no public URL, which can expire), then reports results back.
set +e
REPO=/workspaces/oc-unlimited-codespaces
mkdir -p "$REPO/results"
REPORT="$REPO/results/report.txt"
exec > "$REPORT" 2>&1

echo "=== BEGIN $(date -u) ==="
echo "USER=$(whoami) HOME=$HOME CODESPACES=${CODESPACES:-unset} CODESPACE_NAME=${CODESPACE_NAME:-unset}"
echo "OS: $(. /etc/os-release; echo "$NAME $VERSION_ID")"
echo "ARCH: $(uname -m)"

SRC="$REPO/install.sh"
echo "sha256=$(sha256sum "$SRC" 2>/dev/null | cut -d' ' -f1) bytes=$(wc -c <"$SRC" 2>/dev/null)"
EXPECTED='17b54dfdde478c9a173b7545f3b8cd49016317e33e7379966d12fbd99cbac919'
ACTUAL=$(sha256sum "$SRC" 2>/dev/null | cut -d' ' -f1)
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "FATAL: installer hash mismatch; refusing to run"
  echo "=== END $(date -u) ==="
  cd "$REPO"; git add -f results/report.txt; git commit -q -m "report"; git push --force origin HEAD:results; exit 1
fi

echo "=== INSTALL ==="
bash "$SRC"
echo "install_exit=$?"

echo "=== OUC STATUS ==="
ouc status 2>&1
echo "=== OUC DOCTOR ==="
ouc doctor 2>&1
echo "=== OPENCODE VERSION ==="
opencode --version 2>&1

PROMPT='فقط این عدد را حساب کن و هیچ چیز دیگری ننویس: (19 × 21) + 7'
echo "=== TEST opencode/big-pickle ==="
opencode run -m opencode/big-pickle "$PROMPT" 2>&1
echo "big_pickle_exit=$?"
echo "=== TEST opencode/flint-40b-free ==="
opencode run -m opencode/flint-40b-free "$PROMPT" 2>&1
echo "flint_exit=$?"
echo "=== END $(date -u) ==="

# Snapshot the finished report, then push back to GitHub.
cd "$REPO" || exit 1
cp "$REPORT" "$REPO/results/report-final.txt"
git add -f results/report.txt results/report-final.txt
git -c user.name=call2sgz -c user.email=siavash@users.noreply.github.com \
  commit -q -m "Codespace install report" 2>&1
git push --force origin HEAD:results 2>&1

if command -v gh >/dev/null 2>&1; then
  B64=$(base64 -w0 "$REPORT")
  gh api -X PUT "repos/call2sgz/oc-unlimited-codespaces/contents/results/report-final.txt" \
    -f message="Codespace install report (gh)" -f content="$B64" -f branch="results" 2>&1
fi
