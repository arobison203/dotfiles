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

used_pct_int=0
[ -n "$used_pct" ] && used_pct_int=$(printf "%.0f" "$used_pct")
filled=$(( used_pct_int / 10 ))
empty=$(( 10 - filled ))
bar=""
# filled blocks: green < 50, yellow < 80, red >= 80
if [ "$used_pct_int" -ge 80 ]; then fill_color="${red}"
elif [ "$used_pct_int" -ge 50 ]; then fill_color="${yellow}"
else fill_color="${green}"; fi
for ((i=0; i<filled; i++)); do bar+="\xe2\x96\x88"; done
filled_bar="${fill_color}${bar}${reset}"
bar=""
for ((i=0; i<empty; i++)); do bar+="\xe2\x96\x88"; done
empty_bar="${dim}${bar}${reset}"
ctx_str="${filled_bar}${empty_bar} ${ctx_used_k}k/${ctx_size_k}k (${used_pct_int}%)"

# ── cost estimate ────────────────────────────────────────────────────────────
cost=$(awk -v tc="$total_cost" -v inp="$total_in" -v out="$total_out" \
  -v cc="$cache_create" -v cr="$cache_read" \
  'BEGIN {
    if (tc + 0 > 0) {
      printf "%.2f", tc
    } else {
      cost = (inp * 15.0 + cc * 18.75 + cr * 1.50 + out * 75.0) / 1000000
      printf "%.2f", cost
    }
  }')
cost_str="${dim}\$${reset}${white}${cost}${reset}"

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

    # Minutes remaining until reset (jq strips microseconds, converts to epoch)
    mins_remaining() {
      local reset_at="$1"
      local reset_epoch now_epoch
      reset_epoch=$(jq -rn --arg t "$reset_at" '$t | gsub("\\.[0-9]+\\+00:00$"; "Z") | fromdateiso8601')
      now_epoch=$(date +%s)
      echo $(( (reset_epoch - now_epoch) / 60 ))
    }

    # Human-readable time until reset
    fmt_ttl() {
      local rm="$1"
      if [ "$rm" -le 0 ]; then echo "now"
      elif [ "$rm" -ge 1440 ]; then echo "$(( rm / 1440 ))d$(( (rm % 1440) / 60 ))h"
      elif [ "$rm" -ge 60 ]; then echo "$(( rm / 60 ))h$(( rm % 60 ))m"
      else echo "${rm}m"
      fi
    }

    # Pace delta: usage% - elapsed%
    # d = u - (w - rm) * 100 / w
    pace_delta() {
      local u="$1" w="$2" rm="$3"
      [ "$rm" -lt 0 ] && rm=0
      echo $(( u - (w - rm) * 100 / w ))
    }

    fmt_delta() {
      local d="$1"
      if [ "$d" -gt 0 ]; then
        printf "${red}\xe2\x86\x91%d%%${reset}" "$d"
      elif [ "$d" -lt 0 ]; then
        printf "${green}\xe2\x86\x93%d%%${reset}" "$(( -d ))"
      else
        printf "${green}\xe2\x86\x930%%${reset}"
      fi
    }

    five_rm=$(mins_remaining "$five_reset")
    seven_rm=$(mins_remaining "$seven_reset")

    five_ttl=$(fmt_ttl "$five_rm")
    seven_ttl=$(fmt_ttl "$seven_rm")

    five_d=$(pace_delta "$five_int" 300 "$five_rm")
    seven_d=$(pace_delta "$seven_int" 10080 "$seven_rm")

    five_delta_str=$(fmt_delta "$five_d")
    seven_delta_str=$(fmt_delta "$seven_d")

    # 5h 3% v39% 2h53m · 7d 4% v89% 1d20h
    usage_str="${dim}5h${reset} ${five_color}${five_int}%${reset} ${five_delta_str} ${dim}${five_ttl}${reset} ${dot} ${dim}7d${reset} ${seven_color}${seven_int}%${reset} ${seven_delta_str} ${dim}${seven_ttl}${reset}"
  fi
fi

# ── token speed ──────────────────────────────────────────────────────────────
speed=$(awk -v tokens="$total_out" -v ms="$api_duration" \
  'BEGIN {
    if (ms + 0 > 0) printf "%.0f", (tokens / ms) * 1000
    else printf "0"
  }')
speed_str="${dim}${speed} tok/s${reset}"

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
line1=()
line2=()

# line 1: location + git + worktree + model + mcp + vim
line1+=("${blue}${short_cwd}${reset}")
[ -n "$git_str" ] && line1+=("$git_str")
[ -n "$worktree_str" ] && line1+=("$worktree_str")
line1+=("${dim}${model}${reset}")
[ -n "$mcp_str" ] && line1+=("$mcp_str")
[ -n "$vim_str" ] && line1+=("$vim_str")

# line 2: context window + cost + speed + usage limits
ctx_group="${ctx_str}"
[ -n "$cost_str" ] && ctx_group+=" ${dot} ${cost_str}"
[ -n "$speed_str" ] && ctx_group+=" ${dot} ${speed_str}"
line2+=("$ctx_group")
[ -n "$usage_str" ] && line2+=("$usage_str")

# join each line with separator
join_parts() {
  local out=""
  for part in "$@"; do
    [ -n "$out" ] && out+="${sep}"
    out+="$part"
  done
  echo -n "$out"
}

output="$(join_parts "${line1[@]}")\n$(join_parts "${line2[@]}")"

printf "%b" "$output"
