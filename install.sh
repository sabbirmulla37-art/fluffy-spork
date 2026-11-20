#!/usr/bin/env bash
# SiftNodes installer/configurator. Review before running; run as a normal user with sudo.
set -Eeuo pipefail
cd "$(dirname "$(readlink -f "$0")")"

if [[ "$(id -u)" -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi

printf '\n=== SiftNodes VPS Bot Setup ===\n'

# Install only required OS packages; Docker is optional and installed from Ubuntu repos.
if [[ "${SIFT_SKIP_INSTALL:-0}" != "1" ]]; then
  if command -v apt-get >/dev/null 2>&1; then
    echo '[1/4] Installing Python and required system packages...'
    $SUDO apt-get update
    $SUDO apt-get install -y python3 python3-venv python3-pip ca-certificates curl
  else
    echo 'This installer currently supports Debian/Ubuntu apt systems.' >&2
    exit 1
  fi
  echo '[2/4] Creating isolated Python environment...'
  python3 -m venv venv
  ./venv/bin/python -m pip install --upgrade pip
  ./venv/bin/python -m pip install 'discord.py>=2.3,<3' 'aiohttp>=3.9,<4'

  read -r -p 'Install Docker Engine from Ubuntu packages? [y/N]: ' DOCKER
  if [[ "$DOCKER" =~ ^[Yy]$ ]]; then
    $SUDO apt-get install -y docker.io
    $SUDO systemctl enable --now docker
    echo 'Docker installed. Note: Ubuntu docker.io may not be the newest upstream Docker release.'
  fi
fi

ENV_FILE="$PWD/sift.env"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"
setkv() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp)"
  grep -v "^${key}=" "$ENV_FILE" > "$tmp" || true
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  cat "$tmp" > "$ENV_FILE"
  rm -f "$tmp"
  chmod 600 "$ENV_FILE"
}

printf '\n[3/4] Configure bot settings\n'
read -r -p 'Website URL (e.g. https://terminal.example.com): ' URL
URL="${URL%/}"
if [[ ! "$URL" =~ ^https?://[^[:space:]]+$ ]]; then
  echo 'Invalid URL. Enter a full http:// or https:// URL.' >&2; exit 1
fi
read -r -p 'Owner Discord User ID (numeric): ' OWNER_ID
if [[ ! "$OWNER_ID" =~ ^[0-9]{15,22}$ ]]; then
  echo 'Invalid Discord ID. Enable Developer Mode and copy your user ID.' >&2; exit 1
fi
read -r -s -p 'Discord bot token (input hidden): ' TOKEN; echo
if [[ -z "$TOKEN" || "$TOKEN" == *$'\n'* ]]; then echo 'Bot token cannot be empty.' >&2; exit 1; fi

setkv SIFT_WEB_URL "$URL"
setkv SIFT_OWNER_ID "$OWNER_ID"
setkv DISCORD_TOKEN "$TOKEN"
unset TOKEN

printf '\n[4/4] Starting SiftNodes...\n'
PY="$PWD/venv/bin/python"
[[ -x "$PY" ]] || PY="$(command -v python3)"
if [[ ! -f "$PWD/sift-v4.py" ]]; then echo 'sift-v4.py not found beside installer.' >&2; exit 1; fi
# Stop only the bot process launched from this exact script path.
if command -v pgrep >/dev/null 2>&1; then
  while read -r pid; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done < <(pgrep -f "${PY//\//\\/} ${PWD//\//\\/}/sift-v4.py" || true)
fi
nohup "$PY" "$PWD/sift-v4.py" >> "$PWD/sift.log" 2>&1 < /dev/null &
echo "Started. View logs: tail -f '$PWD/sift.log'"
echo "Config saved with permissions 600 in: $ENV_FILE"
echo 'Keep sift.env private; it contains your Discord bot token.'
