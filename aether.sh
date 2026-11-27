#!/usr/bin/env bash
# ouc-aether — truly unlimited OpenCode via rotating Aether WARP identities.
#
# Each identity is a freshly registered Cloudflare WARP account with its own
# IPv6 /64. Aether carries the tunnel over MASQUE / HTTP-2 (TCP 443), which is
# open in GitHub Codespaces, and exposes a local HTTP CONNECT proxy. When the
# OpenCode free tier answers 429/403, the identity is rotated (new /64, new
# exit address) and the request is retried. No warp-cli, no systemd, no TUN,
# no firewall, no global proxy, no edits to any other OpenCode install.
set -uo pipefail

AETHER_BIN="${AETHER_BIN:-$HOME/.local/bin/aether-tunnel}"
OPENCODE_BIN="${OPENCODE_BIN:-$HOME/.opencode/bin/opencode}"
IDIR="${OUC_IDENTITY_DIR:-$HOME/.local/state/ouc-aether/identities}"
HTTP_PORT="${OUC_HTTP_PORT:-1820}"
SOCKS_PORT="${OUC_SOCKS_PORT:-1819}"
PEER="${OUC_PEER:-162.159.198.131:443}"
API="${OUC_API_ADDRESS:-162.159.137.105}"
MAX_ROT="${OUC_MAX_ROTATIONS:-8}"
LOG="$IDIR/tunnel.log"
PIDF="$IDIR/tunnel.pid"

mkdir -p "$IDIR" || { echo "cannot create $IDIR" >&2; exit 1; }

# ---------------------------------------------------------------- install ---
do_install() {
  command -v curl >/dev/null || { echo "curl missing" >&2; return 1; }
  command -v tar >/dev/null || { echo "tar missing" >&2; return 1; }
  if [ ! -x "$OPENCODE_BIN" ]; then
    echo "Installing pinned OpenCode 2.2.7 ..." >&2
    local stage tgz bin
    stage=$(mktemp -d)
    tgz="$stage/opencode.tgz"
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 600 \
      'https://registry.npmjs.org/@opencode/cli-linux-x64/-/cli-linux-x64-2.2.7.tgz' -o "$tgz" || return 1
    echo "wk/DPHxr4maiW+FmQp8ztoXlo/vC5qsmEIHsLNaNLZL2iaIYfhyqFRe6CRsCVxy+ib0sfK07X2IepFw7ZSKqNQ==" \
      | sed 's/ *$//' > "$stage/want.sha512"
    # sha512sum output is "<hex>  <file>"; compare only the hex.
    local got
    got=$(sha512sum "$tgz" | awk '{print $1}')
    local want
    want=$(base64 -d "$stage/want.sha512" | od -An -tx1 | tr -d ' \n')
    [ "$got" = "$want" ] || { echo "tarball integrity mismatch" >&2; return 1; }
    tar -xzf "$tgz" -C "$stage" || return 1
    bin=$(find "$stage" -type f -name opencode | head -1)
    [ -n "$bin" ] || { echo "no opencode binary in tarball" >&2; return 1; }
    local bsha
    bsha=$(sha256sum "$bin" | awk '{print $1}')
    [ "$bsha" = "589253d36810f21217edd51545cd435b328cdc3cf4f451fbe0cce6f88afcf5e1" ] || {
      echo "binary sha mismatch" >&2; return 1; }
    chmod 0755 "$bin"
    mkdir -p "$(dirname "$OPENCODE_BIN")"
    cp "$bin" "$OPENCODE_BIN" || return 1
    "$OPENCODE_BIN" --version 2>&1 | head -1 >&2 || return 1
    rm -rf "$stage"
    echo "  OpenCode ready" >&2
  fi
  if [ ! -x "$AETHER_BIN" ]; then
    local SRC
    SRC="$(cd "$(dirname "$0")" && pwd)/bin/aether-tunnel"
    [ -x "$SRC" ] || { echo "bundled aether binary not found: $SRC" >&2; return 1; }
    mkdir -p "$(dirname "$AETHER_BIN")"
    cp "$SRC" "$AETHER_BIN" && chmod 0755 "$AETHER_BIN" || return 1
    echo "  aether-tunnel installed" >&2
  fi
  # Optional system-wide `ouc` command (best effort; user bin always works).
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo -n install -m 0755 "$(readlink -f "$0")" /usr/local/bin/ouc 2>/dev/null || true
  else
    mkdir -p "$HOME/.local/bin"
    cp "$(readlink -f "$0")" "$HOME/.local/bin/ouc" 2>/dev/null && chmod +x "$HOME/.local/bin/ouc" || true
  fi
  echo "install done" >&2
}

# ------------------------------------------------------------ registration ---
register_identity() {
  local base="$IDIR/id-$(date +%s%N)-$$"
  "$AETHER_BIN" --register masque --config "$base" --api-address "$API" >>"$LOG" 2>&1
  local cfg=""
  for c in "$base-masque.toml" "$base.toml" "$base-masque" "$base"; do
    [ -f "$c" ] && { cfg="$c"; break; }
  done
  [ -n "$cfg" ] || return 1
  echo "$cfg"
}

tunnel_running() {
  local pid
  [ -f "$PIDF" ] && pid=$(cat "$PIDF") && kill -0 "$pid" 2>/dev/null && return 0
  return 1
}

start_tunnel() {
  local cfg="$1"
  : > "$LOG"
  "$AETHER_BIN" --masque --h2 --dual --balanced --no-quick-reconnect \
    --validate-secs 30 --reconnect-secs 3 --peer "$PEER" \
    --bind "127.0.0.1:$SOCKS_PORT" --http-proxy "127.0.0.1:$HTTP_PORT" \
    --config "$cfg" >>"$LOG" 2>&1 &
  echo $! > "$PIDF"
  for i in $(seq 1 30); do
    grep -qi 'http proxy listening' "$LOG" && return 0
    kill -0 "$(cat "$PIDF")" 2>/dev/null || return 1
    sleep 2
  done
  return 1
}

stop_tunnel() {
  if [ -f "$PIDF" ]; then
    kill "$(cat "$PIDF")" 2>/dev/null
    wait "$(cat "$PIDF")" 2>/dev/null
    rm -f "$PIDF"
  fi
}

do_up() {
  if tunnel_running; then echo "tunnel already up" >&2; return 0; fi
  local cfg
  cfg=$(register_identity) || { echo "registration failed" >&2; tail -5 "$LOG" >&2; return 1; }
  start_tunnel "$cfg" || { echo "tunnel failed" >&2; tail -10 "$LOG" >&2; return 1; }
  echo "tunnel up: $(grep -o 'exit: [^,]*' "$LOG" | tail -1)" >&2
}

do_hop() {
  stop_tunnel
  do_up
}

# ------------------------------------------------------------- headless run ---
do_run() {
  local prompt="$*" attempt
  [ -n "$prompt" ] || { echo "usage: ouc run <prompt>" >&2; return 2; }
  for attempt in $(seq 1 "$MAX_ROT"); do
    do_up || { echo "up failed on attempt $attempt" >&2; continue; }
    local out
    out=$(HTTP_PROXY="http://127.0.0.1:$HTTP_PORT" HTTPS_PROXY="http://127.0.0.1:$HTTP_PORT" \
          http_proxy="http://127.0.0.1:$HTTP_PORT" https_proxy="http://127.0.0.1:$HTTP_PORT" \
          "$OPENCODE_BIN" run "$prompt" 2>&1)
    if grep -qEi 'FreeUsageLimitError|FreeTierError|429|temporarily rate-limited|upstream rate-limited' <<<"$out"; then
      echo "OUC: quota wall on attempt $attempt — rotating identity ..." >&2
      stop_tunnel
      continue
    fi
    printf '%s\n' "$out"
    return 0
  done
  echo "OUC: exhausted $MAX_ROT rotations" >&2
  return 1
}

# -------------------------------------------------------------- interactive ---
do_interactive() {
  do_up || return 1
  export HTTP_PROXY="http://127.0.0.1:$HTTP_PORT" HTTPS_PROXY="$HTTP_PROXY"
  export http_proxy="$HTTP_PROXY" https_proxy="$HTTP_PROXY"
  export NO_PROXY="localhost,127.0.0.1,::1"; export no_proxy="$NO_PROXY"
  echo "OUC ready — rotate egress any time with: ouc hop" >&2
  exec "$OPENCODE_BIN" "$@"
}

case "${1:-}" in
  install) shift; do_install "$@" ;;
  up)      do_up ;;
  hop)     do_hop ;;
  run)     shift; do_run "$@" ;;
  stop)    stop_tunnel ;;
  *)       do_interactive "$@" ;;
esac
