#!/usr/bin/env bash
input=$(cat)

# ── colors ────────────────────────────────────────────────────────────────────
reset="\033[0m"
dim="\033[2m"
bold="\033[1m"
cyan="\033[36m"
green="\033[32m"
yellow="\033[33m"
red="\033[31m"
blue="\033[34m"
magenta="\033[35m"
white="\033[37m"
bg_dim="\033[48;5;236m"

sep="${dim} \xe2\x94\x82 ${reset}"
dot="${dim}\xc2\xb7${reset}"

# ── extract JSON fields ──────────────────────────────────────────────────────
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
[ -z "$cwd" ] && cwd=$(pwd)
cwd="${cwd/#$HOME/~}"

model=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
model="${model/Claude /}"

used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
input_t=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
output_t=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
total_duration=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
api_duration=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')

vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')
wt_name=$(echo "$input" | jq -r '.worktree.name // empty')
wt_branch=$(echo "$input" | jq -r '.worktree.branch // empty')

# ── cwd (shortened) ─────────────────────────────────────────────────────────
short_cwd="$cwd"

# ── context window ───────────────────────────────────────────────────────────
ctx_used=$(( input_t + cache_create + cache_read ))
ctx_size_k=$(( ctx_size / 1000 ))
ctx_used_k=$(( ctx_used / 1000 ))

if [ -n "$used_pct" ]; then
  used_pct_int=$(printf "%.0f" "$used_pct")
  if [ "$used_pct_int" -ge 80 ]; then
    ctx_color="${red}"
    ctx_icon="\xe2\x96\x93"  # dark shade
  elif [ "$used_pct_int" -ge 50 ]; then
    ctx_color="${yellow}"
    ctx_icon="\xe2\x96\x92"  # medium shade
  elif [ "$used_pct_int" -ge 25 ]; then
    ctx_color="${white}"
    ctx_icon="\xe2\x96\x91"  # light shade
  else
    ctx_color="${green}"
    ctx_icon="\xe2\x96\x91"  # light shade
  fi
  ctx_str="${ctx_color}${ctx_icon} ${ctx_used_k}k/${ctx_size_k}k (${used_pct_int}%)${reset}"
else
  ctx_str="${dim}--${reset}"
fi

# ── cost estimate ────────────────────────────────────────────────────────────
cost_str=""
if [ "$total_in" -gt 0 ] || [ "$total_out" -gt 0 ]; then
  # Use cost.total_cost_usd if available and non-zero, otherwise calculate
  cost=$(awk -v tc="$total_cost" -v inp="$total_in" -v out="$total_out" \
    -v cc="$cache_create" -v cr="$cache_read" \
    'BEGIN {
      if (tc + 0 > 0) {
        printf "%.2f", tc
      } else {
        # Opus 4 rates: $15/M in, $18.75/M cache write, $1.50/M cache read, $75/M out
        cost = (inp * 15.0 + cc * 18.75 + cr * 1.50 + out * 75.0) / 1000000
        printf "%.2f", cost
      }
    }')
  cost_str="${dim}\$${reset}${white}${cost}${reset}"
fi

# ── usage limits (5hr / 7day) ────────────────────────────────────────────────
usage_str=""
usage_cache="/tmp/.claude-usage-cache"
usage_ttl=60  # seconds

fetch_usage() {
  local token_json
  token_json=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || return 1
  local token
  token=$(echo "$token_json" | jq -r '.claudeAiOauth.accessToken // .accessToken // empty' 2>/dev/null)
  [ -z "$token" ] && return 1

  curl -sf --max-time 3 \
    -H "Authorization: Bearer ${token}" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null
}

# Use cache if fresh enough, otherwise fetch in background
if [ -f "$usage_cache" ]; then
  cache_age=$(( $(date +%s) - $(stat -f %m "$usage_cache" 2>/dev/null || echo 0) ))
  if [ "$cache_age" -gt "$usage_ttl" ]; then
    # Stale -- refresh in background, use stale data for now
    ( fetch_usage > "${usage_cache}.tmp" 2>/dev/null && mv "${usage_cache}.tmp" "$usage_cache" ) &
  fi
  usage_json=$(cat "$usage_cache" 2>/dev/null)
else
  # No cache -- fetch synchronously (first run only)
  usage_json=$(fetch_usage 2>/dev/null)
  [ -n "$usage_json" ] && echo "$usage_json" > "$usage_cache"
fi

if [ -n "$usage_json" ]; then
  five_hr=$(echo "$usage_json" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
  seven_day=$(echo "$usage_json" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
  five_reset=$(echo "$usage_json" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
  seven_reset=$(echo "$usage_json" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)

  if [ -n "$five_hr" ] && [ -n "$seven_day" ]; then
    five_int=$(printf "%.0f" "$five_hr")
    seven_int=$(printf "%.0f" "$seven_day")

    # Color by severity
    if [ "$five_int" -ge 80 ]; then five_color="${red}"
    elif [ "$five_int" -ge 50 ]; then five_color="${yellow}"
    else five_color="${green}"; fi

    if [ "$seven_int" -ge 80 ]; then seven_color="${red}"
    elif [ "$seven_int" -ge 50 ]; then seven_color="${yellow}"
    else seven_color="${green}"; fi

    # Calculate time until reset
    time_until() {
      local reset_ts now_ts diff_s hours mins
      # Use python to handle ISO 8601 with timezone correctly
      reset_ts=$(python3 -c "
from datetime import datetime, timezone
import sys
try:
    dt = datetime.fromisoformat(sys.argv[1])
    print(int(dt.timestamp()))
except: pass
" "$1" 2>/dev/null)
      [ -z "$reset_ts" ] && return
      now_ts=$(date +%s)
      diff_s=$(( reset_ts - now_ts ))
      [ "$diff_s" -le 0 ] && echo "now" && return
      hours=$(( diff_s / 3600 ))
      mins=$(( (diff_s % 3600) / 60 ))
      if [ "$hours" -gt 24 ]; then
        local days=$(( hours / 24 ))
        hours=$(( hours % 24 ))
        echo "${days}d${hours}h"
      elif [ "$hours" -gt 0 ]; then
        echo "${hours}h${mins}m"
      else
        echo "${mins}m"
      fi
    }

    five_ttl=$(time_until "$five_reset")
    seven_ttl=$(time_until "$seven_reset")

    five_reset_str=""
    [ -n "$five_ttl" ] && five_reset_str="${dim}@${five_ttl}${reset}"
    seven_reset_str=""
    [ -n "$seven_ttl" ] && seven_reset_str="${dim}@${seven_ttl}${reset}"

    usage_str="${dim}5h:${reset}${five_color}${five_int}%${reset}${five_reset_str} ${dim}7d:${reset}${seven_color}${seven_int}%${reset}${seven_reset_str}"
  fi
fi

# ── token speed ──────────────────────────────────────────────────────────────
speed_str=""
if [ "$api_duration" -gt 0 ] && [ "$total_out" -gt 0 ]; then
  speed=$(awk -v tokens="$total_out" -v ms="$api_duration" \
    'BEGIN { printf "%.0f", (tokens / ms) * 1000 }')
  speed_str="${dim}${speed} tok/s${reset}"
fi

# ── git info ─────────────────────────────────────────────────────────────────
git_str=""
if git rev-parse --is-inside-work-tree &>/dev/null; then
  branch=$(git -c gc.auto=0 rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    main_branch=$(git -c gc.auto=0 symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    [ -z "$main_branch" ] && main_branch="main"

    ahead=$(git -c gc.auto=0 rev-list --count "${main_branch}..HEAD" 2>/dev/null || echo "0")

    # Dirty status breakdown
    staged=$(git -c gc.auto=0 diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    modified=$(git -c gc.auto=0 diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    untracked=$(git -c gc.auto=0 ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

    dirty_parts=""
    [ "$staged" -gt 0 ] && dirty_parts+="${yellow}+${staged}${reset}"
    [ "$modified" -gt 0 ] && { [ -n "$dirty_parts" ] && dirty_parts+=" "; dirty_parts+="${yellow}!${modified}${reset}"; }
    [ "$untracked" -gt 0 ] && { [ -n "$dirty_parts" ] && dirty_parts+=" "; dirty_parts+="${blue}?${untracked}${reset}"; }

    if [ -n "$dirty_parts" ]; then
      dirty_str=" ${dirty_parts}"
    else
      dirty_str=""
    fi

    commits_str=""
    [ "$ahead" -gt 0 ] && commits_str=" ${cyan}\xe2\x86\x91${ahead}${reset}"

    git_str="${magenta}${branch}${reset}${commits_str}${dirty_str}"
  fi
fi

# ── mcp servers ──────────────────────────────────────────────────────────────
mcp_str=""
# Check for .mcp.json in project dir or cwd
real_cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
[ -z "$real_cwd" ] && real_cwd=$(pwd)

mcp_file=""
[ -f "${real_cwd}/.mcp.json" ] && mcp_file="${real_cwd}/.mcp.json"
[ -z "$mcp_file" ] && [ -f "$HOME/.claude/.mcp.json" ] && mcp_file="$HOME/.claude/.mcp.json"

if [ -n "$mcp_file" ]; then
  server_names=$(jq -r '.mcpServers // {} | keys[]' "$mcp_file" 2>/dev/null)
  if [ -n "$server_names" ]; then
    count=$(echo "$server_names" | wc -l | tr -d ' ')
    # Show names if 3 or fewer, otherwise just count
    if [ "$count" -le 3 ]; then
      names=$(echo "$server_names" | paste -sd',' -)
      mcp_str="${dim}mcp:${reset}${cyan}${names}${reset}"
    else
      mcp_str="${dim}mcp:${reset}${cyan}${count}${reset}"
    fi
  fi
fi

# ── vim mode ─────────────────────────────────────────────────────────────────
vim_str=""
if [ -n "$vim_mode" ]; then
  if [ "$vim_mode" = "NORMAL" ]; then
    vim_str="${bold}${blue}NRM${reset}"
  else
    vim_str="${bold}${green}INS${reset}"
  fi
fi

# ── worktree ─────────────────────────────────────────────────────────────────
worktree_str=""
if [ -n "$wt_name" ]; then
  if [ -n "$wt_branch" ]; then
    worktree_str="${dim}wt:${reset}${cyan}${wt_name}(${wt_branch})${reset}"
  else
    worktree_str="${dim}wt:${reset}${cyan}${wt_name}${reset}"
  fi
fi

# ── assemble ─────────────────────────────────────────────────────────────────
parts=()

# left group: location + git
parts+=("${blue}${short_cwd}${reset}")
[ -n "$git_str" ] && parts+=("$git_str")
[ -n "$worktree_str" ] && parts+=("$worktree_str")

# middle group: model + context + cost + speed
model_group="${dim}${model}${reset} ${ctx_str}"
[ -n "$cost_str" ] && model_group+=" ${dot} ${cost_str}"
[ -n "$speed_str" ] && model_group+=" ${dot} ${speed_str}"
parts+=("$model_group")

# usage limits
[ -n "$usage_str" ] && parts+=("$usage_str")

# right group: mcp + vim
[ -n "$mcp_str" ] && parts+=("$mcp_str")
[ -n "$vim_str" ] && parts+=("$vim_str")

# join with separator
output=""
for i in "${!parts[@]}"; do
  [ $i -gt 0 ] && output+="${sep}"
  output+="${parts[$i]}"
done

printf "%b" "$output"
