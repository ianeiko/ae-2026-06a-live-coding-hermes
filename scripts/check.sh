#!/usr/bin/env bash
# Prints ok / MISSING for every setup step in README.md and names the section that fixes it.
# Spends up to two OpenRouter API calls: one to validate the key, one to prove a :free
# model is actually reachable (the §1 privacy toggle). Both are free.
cd "$(dirname "$0")/.."
fail=0
PY=$(command -v python3 || command -v python)   # python3 on macOS, often just python on Windows
ok()   { printf 'ok       %s\n' "$1"; }
miss() { printf 'MISSING  %-38s -> %s\n' "$1" "$2"; fail=1; }
todo() { printf 'todo     %-38s -> %s\n' "$1" "$2"; }   # not your job yet
note() { printf '         %s\n' "$1"; }

FREE_MODEL="nvidia/nemotron-3-ultra-550b-a55b:free"

# --- right directory? ---
[ -f README.md ] && ok "README.md" || miss "README.md not found" "run this from the repo root"
[ -f .env.example ] && ok ".env.example" || todo ".env.example missing" "§3 — not fatal, but the template is gone"

# --- tools (§2) ---
if command -v docker >/dev/null 2>&1; then
  ok "docker ($(docker --version 2>/dev/null | awk '{print $3}' | tr -d ,))"
  if docker info >/dev/null 2>&1; then
    ok "docker daemon is running"
  else
    miss "docker installed but not running" "§2 — start Docker Desktop, wait, re-run"
  fi
else
  miss "docker" "§2 Tools — brew install --cask docker"
fi

if command -v spawn >/dev/null 2>&1; then ok "spawn ($(spawn version 2>/dev/null | head -1 | tr -d '\r'))"
else miss "spawn" "§2 Tools — curl -fsSL https://openrouter.ai/labs/spawn/cli/install.sh | bash"; fi

command -v curl >/dev/null 2>&1 && ok "curl" || miss "curl" "§2 — needed for the key checks below"
command -v git  >/dev/null 2>&1 && ok "git"  || todo "git" "Appendix B"

# --- the key (§3) ---
# Same precedence spawn uses: a real export wins, then ./.env, then spawn's cache.
read_env_file() {   # $1 = file, $2 = var name. BRE \\+ and \\? are GNU-only, so grep -E does the matching.
  [ -f "$1" ] || return 1
  grep -E "^[[:space:]]*(export[[:space:]]+)?$2[[:space:]]*=" "$1" 2>/dev/null \
    | tail -1 \
    | sed -e 's/^[^=]*=//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
          -e 's/^"//' -e "s/^'//" -e 's/"$//' -e "s/'$//" \
    | tr -d '\r'
}

KEY=""
KEYSRC=""
if [ -n "$OPENROUTER_API_KEY" ]; then
  KEY="$OPENROUTER_API_KEY"; KEYSRC="OPENROUTER_API_KEY (exported)"
else
  K=$(read_env_file .env OPENROUTER_API_KEY)
  [ -f .env ] && [ -z "$K" ] && ENV_BLANK=1
  if [ -n "$K" ]; then
    KEY="$K"; KEYSRC="./.env"
  elif [ -f "$HOME/.config/spawn/openrouter.json" ] && [ -n "$PY" ]; then
    KEY=$("$PY" -c 'import json,os,sys
try:
    print(json.load(open(os.path.expanduser("~/.config/spawn/openrouter.json"))).get("api_key",""))
except Exception:
    pass' 2>/dev/null | tr -d '\r')
    [ -n "$KEY" ] && KEYSRC="~/.config/spawn/openrouter.json (cached from a previous run)"
  fi
fi

if [ -n "$KEY" ]; then
  ok "OpenRouter key (from $KEYSRC)"
  case "$KEYSRC" in
    *cached*)
      if [ "$ENV_BLANK" = 1 ]; then
        note "./.env exists but OPENROUTER_API_KEY is empty — this is a stale cached key, not yours (§3)"
      else
        note "no ./.env here — spawn is reusing an old key. §3, if that's not the one you meant."
      fi ;;
  esac
else
  if [ -f .env ]; then
    miss "no key in ./.env" "§3 — put OPENROUTER_API_KEY=sk-or-v1-... in it"
  else
    miss "no ./.env and no key" "§3 — cp .env.example .env, then paste your key"
  fi
fi

# --- is .env leaking into git? (§3) ---
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  if git ls-files --error-unmatch .env >/dev/null 2>&1; then
    miss ".env is TRACKED BY GIT" "§3 — git rm --cached .env, and check it never got pushed"
    note "your key is in the repo history from the moment you commit. Rotate it if it left this machine."
  elif [ -f .env ]; then
    if git check-ignore -q .env 2>/dev/null; then ok ".env exists and is gitignored"
    else miss ".env is NOT gitignored" "§3 — add a .env line to .gitignore before you commit"; fi
  fi
fi

# Nothing past here can work without a key, and guessing would only add noise.
if [ -z "$KEY" ] || ! command -v curl >/dev/null 2>&1; then
  todo "key + free-model checks skipped" "§3 first, then re-run"
  echo "fix the MISSING lines, then re-run"
  exit 1
fi

# --- does the key authenticate? (§3) ---
KEYINFO=$(curl -s --max-time 20 https://openrouter.ai/api/v1/key -H "Authorization: Bearer $KEY" 2>/dev/null)
if echo "$KEYINFO" | grep -q '"data"'; then
  ok "OpenRouter accepted the key"
  [ -n "$PY" ] && echo "$KEYINFO" | "$PY" -c '
import json, sys
try:
    d = json.load(sys.stdin)["data"]
except Exception:
    sys.exit(0)
fm = d.get("free_model_daily_requests") or {}
if fm.get("limit") is not None:
    print("         free-model quota today: %s of %s left" % (fm.get("remaining"), fm.get("limit")))
' 2>/dev/null
elif echo "$KEYINFO" | grep -qi 'invalid\|unauthor\|"error"'; then
  miss "OpenRouter rejected the key" "§3 — copy it again from openrouter.ai/settings/keys"
  echo "fix the MISSING lines, then re-run"; exit 1
else
  miss "couldn't reach OpenRouter (offline?)" "§3 — check your connection, re-run"
  echo "fix the MISSING lines, then re-run"; exit 1
fi

# --- is a :free model actually routable? (§1 privacy toggle — the §5 trap, caught early) ---
BODY="{\"model\":\"$FREE_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":1}"
RESP=$(curl -s --max-time 25 https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d "$BODY" 2>/dev/null)
CURL_RC=$?

if [ $CURL_RC = 28 ] || [ -z "$RESP" ]; then
  todo "free model didn't answer in 25s" "not a failure — §5, free endpoints queue"
  note "re-run later, or use the paid twin: ${FREE_MODEL%:free}"
elif echo "$RESP" | grep -qi 'training violation\|data policy'; then
  miss "free models are blocked for this account" "§1 — https://openrouter.ai/settings/privacy"
  note "this is the 404 from §5. The model exists; your account policy filtered it."
elif echo "$RESP" | grep -q '"choices"'; then
  ok "free model is routable ($FREE_MODEL)"
elif echo "$RESP" | grep -qi 'rate limit\|429'; then
  todo "free-model rate limit hit" "not a failure — wait, or §5's paid twin"
else
  todo "unexpected reply from the free model" "§5 — read it yourself:"
  echo "$RESP" | head -c 300 | sed 's/^/         /'; echo
fi

# --- has a sandbox been launched yet? (§4, §6) ---
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  RUNNING=$(docker ps --filter 'ancestor=ghcr.io/openrouterteam/spawn-hermes:latest' --format '{{.Names}}' 2>/dev/null | head -1)
  if [ -n "$RUNNING" ]; then
    ok "a hermes sandbox is running ($RUNNING)"
    MNT=$(docker inspect "$RUNNING" --format '{{json .Mounts}}' 2>/dev/null)
    [ "$MNT" = "[]" ] && note "its Mounts are [] — nothing of yours is inside it, and nothing in it survives (§6)"
  else
    todo "no sandbox running yet" "§4 — spawn hermes sandbox --name hermes-lab"
  fi
fi

[ $fail = 0 ] && echo "all set — go to §4" || echo "fix the MISSING lines, then re-run"
exit $fail
