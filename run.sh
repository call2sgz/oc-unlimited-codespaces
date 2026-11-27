#!/usr/bin/env bash
# Runs automatically via devcontainer postCreateCommand.
# Installs the Codespaces-only unlimited-opencode bundle, then reports results
# back to this repo via `gh`/git so the agent can read them from the outside.
set +e
REPO=/workspaces/oc-unlimited-codespaces
mkdir -p "$REPO/results"
REPORT="$REPO/results/report.txt"
exec > "$REPORT" 2>&1

echo "=== BEGIN $(date -u) ==="
echo "USER=$(whoami) HOME=$HOME CODESPACES=${CODESPACES:-unset} CODESPACE_NAME=${CODESPACE_NAME:-unset}"
echo "OS: $(. /etc/os-release; echo "$NAME $VERSION_ID")"
echo "ARCH: $(uname -m)"

URL='https://tmpfiles.org/dl/1795762326.c230ac0f4373e78d/wfAQvXXUfBh7/install.sh'
curl -fsSL "$URL" -o /tmp/ouc-install.sh
echo "curl_exit=$? bytes=$(wc -c </tmp/ouc-install.sh 2>/dev/null)"
echo "sha256=$(sha256sum /tmp/ouc-install.sh 2>/dev/null | cut -d' ' -f1)"
echo "=== INSTALL ==="
bash /tmp/ouc-install.sh
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

# Report back to GitHub: primary via gh API, fallback via git push.
cd "$REPO" || exit 1
git add -f results/report.txt 2>/dev/null
git -c user.name=call2sgz -c user.email=siavash@users.noreply.github.com \
  commit -q -m "Codespace install report" 2>&1
echo "commit_exit=$?"
git push origin HEAD:results 2>&1
echo "git_push_exit=$?"

if command -v gh >/dev/null 2>&1; then
  B64=$(base64 -w0 "$REPORT")
  gh api -X PUT "repos/call2sgz/oc-unlimited-codespaces/contents/results/report.txt" \
    -f message="Codespace install report (gh)" -f content="$B64" -f branch="results" 2>&1
  echo "gh_api_exit=$?"
else
  echo "gh_api_exit=NO_GH"
fi
