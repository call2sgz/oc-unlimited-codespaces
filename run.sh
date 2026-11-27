#!/usr/bin/env bash
# Runs automatically via devcontainer postCreateCommand.
# Proves the Aether-based unlimited lane: fresh WARP identity -> MASQUE/TCP-443
# tunnel -> OpenCode free model -> clean 406, with rotation on quota walls.
set +e
REPO=/workspaces/oc-unlimited-codespaces
mkdir -p "$REPO/results"
REPORT="$REPO/results/aetherlab.txt"
exec > "$REPORT" 2>&1

PROMPT='فقط این عدد را حساب کن و هیچ چیز دیگری ننویس: (19 × 21) + 7'
echo "=== BEGIN $(date -u) ==="
echo "USER=$(whoami) CODESPACES=${CODESPACES:-unset} CODESPACE_NAME=${CODESPACE_NAME:-unset}"
echo "glibc=$(ldd --version 2>&1 | head -1)"
echo "=== INSTALL ==="
bash "$REPO/aether.sh" install 2>&1 | tail -15
echo "install_rc=${PIPESTATUS[0]}"
echo "=== binaries ==="
ls -l /usr/local/bin/aether-tunnel "$HOME/.opencode/bin/opencode" 2>&1
echo "=== AETHER TEST ==="
bash "$REPO/aether.sh" run "$PROMPT" 2>&1
echo "run_rc=$?"
echo "=== TUNNEL LOG TAIL ==="
tail -12 "$HOME/.local/state/ouc-aether/identities/tunnel.log" 2>/dev/null
echo "=== IDENTITY FILES ==="
ls -1 "$HOME/.local/state/ouc-aether/identities/" 2>/dev/null | head -20
echo "=== END $(date -u) ==="

cd "$REPO" || exit 1
cp "$REPORT" "$REPO/results/report-final.txt"
git add -f results/ 2>&1
git -c user.name=call2sgz -c user.email=siavash@users.noreply.github.com commit -q -m "Aether lab results" 2>&1
git push --force origin HEAD:results 2>&1 | tail -3
