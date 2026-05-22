#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
codex_home="${CODEX_HOME:-$HOME/.codex}"
repo_name="$(basename "$repo_root")"

mkdir -p "$codex_home" "$codex_home/skills" "$HOME/.agents/skills"

if [ -f "$repo_root/AGENTS.md" ]; then
  cp "$repo_root/AGENTS.md" "$codex_home/AGENTS.md"
fi

if [ -d "$repo_root/.agents/skills" ]; then
  find "$repo_root/.agents/skills" -mindepth 1 -maxdepth 1 -type d -exec cp -R {} "$HOME/.agents/skills/" \;
  find "$repo_root/.agents/skills" -mindepth 1 -maxdepth 1 -type d -exec cp -R {} "$codex_home/skills/" \;
fi

normalize_bearer() {
  if [ -n "${GBRAIN_MCP_AUTHORIZATION:-}" ]; then
    printf '%s\n' "$GBRAIN_MCP_AUTHORIZATION"
    return 0
  fi

  if [ -n "${GBRAIN_MCP_BEARER_TOKEN:-}" ]; then
    case "$GBRAIN_MCP_BEARER_TOKEN" in
      Bearer\ *) printf '%s\n' "$GBRAIN_MCP_BEARER_TOKEN" ;;
      *) printf 'Bearer %s\n' "$GBRAIN_MCP_BEARER_TOKEN" ;;
    esac
  fi
}

write_codex_config() {
  local auth_header
  local gbrain_url

  auth_header="$(normalize_bearer || true)"
  gbrain_url="${GBRAIN_MCP_URL:-https://openclaw-gateway.tail27d90c.ts.net:3131/mcp}"

  cat > "$codex_home/config.toml" <<TOML
[mcp]
remote_mcp_client_enabled = true

[mcp_servers.gbrain]
url = "$gbrain_url"
startup_timeout_sec = 30
tool_timeout_sec = 120
TOML

  if [ -n "$auth_header" ]; then
    cat >> "$codex_home/config.toml" <<TOML

[mcp_servers.gbrain.http_headers]
Authorization = "$auth_header"
TOML
  else
    cat >> "$codex_home/config.toml" <<'TOML'

[mcp_servers.gbrain.env_http_headers]
Authorization = "GBRAIN_MCP_AUTHORIZATION"
TOML
  fi

  cat >> "$codex_home/config.toml" <<'TOML'

[memories]
generate_memories = true
no_memories_if_mcp_or_web_search = false
use_memories = true
TOML
}

install_curated_skills() {
  local skills
  local missing=()
  local tmp

  skills=(transcribe speech screenshot sentry jupyter-notebook cli-creator migrate-to-codex)

  for skill in "${skills[@]}"; do
    if [ ! -f "$codex_home/skills/$skill/SKILL.md" ]; then
      missing+=("$skill")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    return 0
  fi

  if ! command -v git >/dev/null 2>&1; then
    echo "warning: git is unavailable; curated skills were not installed" >&2
    return 0
  fi

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  git clone --depth 1 --filter=blob:none --sparse https://github.com/openai/skills "$tmp/openai-skills" >/dev/null 2>&1 || {
    echo "warning: unable to clone openai/skills; curated skills were not installed" >&2
    return 0
  }

  (
    cd "$tmp/openai-skills"
    git sparse-checkout set \
      skills/.curated/transcribe \
      skills/.curated/speech \
      skills/.curated/screenshot \
      skills/.curated/sentry \
      skills/.curated/jupyter-notebook \
      skills/.curated/cli-creator \
      skills/.curated/migrate-to-codex >/dev/null 2>&1
  )

  for skill in "${missing[@]}"; do
    if [ -d "$tmp/openai-skills/skills/.curated/$skill" ]; then
      rm -rf "$codex_home/skills/$skill"
      cp -R "$tmp/openai-skills/skills/.curated/$skill" "$codex_home/skills/$skill"
    else
      echo "warning: curated skill not found in openai/skills: $skill" >&2
    fi
  done
}

maybe_start_tailscale() {
  if [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
    return 0
  fi

  if ! command -v tailscale >/dev/null 2>&1; then
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL --connect-timeout 10 --max-time 120 https://tailscale.com/install.sh | sh || {
        echo "warning: tailscale install failed; GBrain may be unreachable from Cloud" >&2
        return 0
      }
    else
      echo "warning: curl is unavailable; cannot install tailscale" >&2
      return 0
    fi
  fi

  if ! command -v tailscaled >/dev/null 2>&1; then
    echo "warning: tailscaled is unavailable after install" >&2
    return 0
  fi

  local ts_socket="$codex_home/tailscaled.sock"
  local ts_state="$codex_home/tailscaled.state"
  local ts_log="$codex_home/tailscaled.log"
  local socks_addr="${TAILSCALE_SOCKS5_ADDR:-127.0.0.1:1055}"
  local http_proxy_addr="${TAILSCALE_HTTP_PROXY_ADDR:-127.0.0.1:1056}"

  nohup tailscaled \
    --tun=userspace-networking \
    --socks5-server="$socks_addr" \
    --outbound-http-proxy-listen="$http_proxy_addr" \
    --socket="$ts_socket" \
    --state="$ts_state" >"$ts_log" 2>&1 &

  sleep 2

  tailscale --socket="$ts_socket" up \
    --authkey "$TAILSCALE_AUTHKEY" \
    --hostname "${TAILSCALE_HOSTNAME:-codex-cloud-$repo_name}" \
    --accept-dns=true \
    --reset || {
      echo "warning: tailscale up failed; see $ts_log" >&2
      return 0
    }

  cat > "$codex_home/cloud-env.sh" <<EOF
export TS_SOCKET="$ts_socket"
export ALL_PROXY="socks5://$socks_addr"
export HTTPS_PROXY="http://$http_proxy_addr"
export HTTP_PROXY="http://$http_proxy_addr"
EOF

  if [ -n "${BASH_ENV:-}" ]; then
    cat "$codex_home/cloud-env.sh" >> "$BASH_ENV"
  fi
}

check_gbrain() {
  local auth_header
  local curl_status
  local stats_url

  if ! command -v curl >/dev/null 2>&1; then
    echo "warning: curl is unavailable; skipped GBrain reachability check" >&2
    return 0
  fi

  auth_header="$(normalize_bearer || true)"
  stats_url="${GBRAIN_MCP_STATS_URL:-https://openclaw-gateway.tail27d90c.ts.net:3131/admin/api/stats}"

  if [ -f "$codex_home/cloud-env.sh" ]; then
    # shellcheck disable=SC1090
    . "$codex_home/cloud-env.sh"
  fi

  if [ -n "$auth_header" ]; then
    curl_status=0
    curl -fsS --connect-timeout 5 --max-time 15 -H "Authorization: $auth_header" "$stats_url" >/dev/null || curl_status=$?
  else
    curl_status=0
    curl -fsS --connect-timeout 5 --max-time 15 "$stats_url" >/dev/null || curl_status=$?
  fi

  if [ "$curl_status" -eq 0 ]; then
    echo "GBrain reachable from Codex Cloud setup."
  elif [ "${REQUIRE_GBRAIN:-0}" = "1" ]; then
    echo "error: GBrain is required but not reachable. Check GBRAIN_MCP_AUTHORIZATION, GBRAIN_MCP_BEARER_TOKEN, TAILSCALE_AUTHKEY, and network access." >&2
    return 1
  else
    echo "warning: GBrain is not reachable yet. The Cloud agent should report the missing secret/network condition instead of using stale memory." >&2
  fi
}

write_codex_config
install_curated_skills
maybe_start_tailscale
check_gbrain

echo "Codex Cloud setup complete for $repo_name. CODEX_HOME=$codex_home"
