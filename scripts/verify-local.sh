#!/usr/bin/env bash
# =============================================================================
# verify-local.sh — Project-specific checks for CLEAR repository compliance
# =============================================================================
# This file is sourced by scripts/verify-ci.sh.
# It enforces shell script quality gates that are project-owned:
#   - shellcheck on tracked *.sh files
#   - shfmt formatting check on tracked *.sh files
#   - bash syntax check on tracked *.sh files
#   - script guardrails for top-level scripts/*.sh
# =============================================================================

set -euo pipefail

section "Shell Script Compliance"

collect_shell_files() {
  local -n out_ref=$1
  out_ref=()

  if command -v git >/dev/null 2>&1 && git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    while IFS= read -r rel_path; do
      [[ -z "$rel_path" ]] && continue
      out_ref+=("$rel_path")
    done < <(cd "$PROJECT_ROOT" && git ls-files '*.sh')
    return 0
  fi

  while IFS= read -r abs_path; do
    [[ -z "$abs_path" ]] && continue
    out_ref+=("${abs_path#"$PROJECT_ROOT/"}")
  done < <(find "$PROJECT_ROOT" -type f -name '*.sh' -print)
}

collect_humans_only_paths() {
  local -n out_ref=$1
  out_ref=()

  local autonomy_file
  autonomy_file="$PROJECT_ROOT/clear/autonomy.yml"
  [[ -f "$autonomy_file" ]] || return 0

  local current_path=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*path:[[:space:]]*(.*)$ ]]; then
      current_path="${BASH_REMATCH[1]}"
      current_path="${current_path#\"}"
      current_path="${current_path%\"}"
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*level:[[:space:]]*humans-only$ ]]; then
      [[ -n "$current_path" ]] && out_ref+=("$current_path")
      current_path=""
    fi
  done < "$autonomy_file"
}

is_humans_only_match() {
  local rel_path="$1"
  shift
  local path_rule
  for path_rule in "$@"; do
    [[ -z "$path_rule" || "$path_rule" == "*" ]] && continue
    if [[ "$rel_path" == "$path_rule" || "$rel_path" == "$path_rule/"* ]]; then
      return 0
    fi
  done
  return 1
}

run_shellcheck_check() {
  local -a abs_files=("$@")

  if ! command -v shellcheck >/dev/null 2>&1; then
    fail "Shellcheck (not installed; install with your package manager)"
    return 1
  fi

  local output_file
  output_file="$(mktemp)"
  if shellcheck -x --severity=error "${abs_files[@]}" >"$output_file" 2>&1; then
    pass "Shellcheck"
  else
    fail "Shellcheck"
    cat "$output_file"
  fi
  rm -f "$output_file"
}

run_shfmt_check() {
  local -a abs_files=("$@")

  if ! command -v shfmt >/dev/null 2>&1; then
    fail "shfmt (not installed; install with your package manager)"
    return 1
  fi

  if [[ "${FIX_MODE:-false}" == "true" ]]; then
    if shfmt -w -i 2 -ci -bn -ln=bash "${abs_files[@]}"; then
      pass "shfmt (auto-fixed)"
      return 0
    fi
    fail "shfmt (auto-fix failed)"
    return 1
  fi

  local output_file
  output_file="$(mktemp)"
  if shfmt -d -i 2 -ci -bn -ln=bash "${abs_files[@]}" >"$output_file" 2>&1; then
    pass "shfmt"
  else
    fail "shfmt"
    cat "$output_file"
  fi
  rm -f "$output_file"
}

run_bash_syntax_check() {
  local -a abs_files=("$@")
  local has_error=false

  for file_path in "${abs_files[@]}"; do
    if ! bash -n "$file_path"; then
      echo "Syntax error: ${file_path#"$PROJECT_ROOT/"}" >&2
      has_error=true
    fi
  done

  if [[ "$has_error" == "true" ]]; then
    fail "Bash syntax"
  else
    pass "Bash syntax"
  fi
}

run_scripts_guardrails_check() {
  local -a scripts_files=("$@")
  local has_error=false

  for abs_path in "${scripts_files[@]}"; do
    local rel_path
    rel_path="${abs_path#"$PROJECT_ROOT/"}"

    if [[ ! -x "$abs_path" ]]; then
      echo "Not executable: $rel_path" >&2
      has_error=true
    fi

    local first_line
    first_line="$(head -n 1 "$abs_path")"
    if [[ "$first_line" != "#!/usr/bin/env bash" ]]; then
      echo "Invalid shebang in $rel_path (expected #!/usr/bin/env bash)" >&2
      has_error=true
    fi

    if ! grep -Eq '^set -euo pipefail$' "$abs_path"; then
      echo "Missing safety flags in $rel_path (expected set -euo pipefail)" >&2
      has_error=true
    fi
  done

  if [[ "$has_error" == "true" ]]; then
    fail "scripts/ guardrails (shebang, safety flags, executable)"
  else
    pass "scripts/ guardrails (shebang, safety flags, executable)"
  fi
}

run_forbidden_pipeline_check() {
  local -a rel_files=("$@")
  local has_error=false

  if command -v rg >/dev/null 2>&1; then
    local match_output
    match_output="$(cd "$PROJECT_ROOT" && rg -n --no-heading 'curl[^\n|]*\|[[:space:]]*bash|wget[^\n|]*\|[[:space:]]*bash' -- "${rel_files[@]}" || true)"
    if [[ -n "$match_output" ]]; then
      echo "$match_output" >&2
      has_error=true
    fi
  else
    local rel_path
    for rel_path in "${rel_files[@]}"; do
      if grep -En 'curl.*\|[[:space:]]*bash|wget.*\|[[:space:]]*bash' "$PROJECT_ROOT/$rel_path" >/dev/null 2>&1; then
        grep -En 'curl.*\|[[:space:]]*bash|wget.*\|[[:space:]]*bash' "$PROJECT_ROOT/$rel_path" >&2 || true
        has_error=true
      fi
    done
  fi

  if [[ "$has_error" == "true" ]]; then
    fail "Forbidden pipe-to-shell patterns"
  else
    pass "Forbidden pipe-to-shell patterns"
  fi
}

shell_rel_files=()
collect_shell_files shell_rel_files
humans_only_paths=()
collect_humans_only_paths humans_only_paths

filtered_rel_files=()
for rel_path in "${shell_rel_files[@]}"; do
  if is_humans_only_match "$rel_path" "${humans_only_paths[@]}"; then
    info "Skipping humans-only shell file: $rel_path"
    continue
  fi
  filtered_rel_files+=("$rel_path")
done

shell_rel_files=("${filtered_rel_files[@]}")

if [[ ${#shell_rel_files[@]} -eq 0 ]]; then
  warn "No tracked shell scripts found; skipping shell compliance checks"
else
  shell_abs_files=()
  for rel_path in "${shell_rel_files[@]}"; do
    shell_abs_files+=("$PROJECT_ROOT/$rel_path")
  done

  run_shellcheck_check "${shell_abs_files[@]}"
  run_shfmt_check "${shell_abs_files[@]}"
  run_bash_syntax_check "${shell_abs_files[@]}"

  scripts_abs_files=()
  for rel_path in "${shell_rel_files[@]}"; do
    if [[ "$rel_path" == scripts/*.sh ]]; then
      scripts_abs_files+=("$PROJECT_ROOT/$rel_path")
    fi
  done

  if [[ ${#scripts_abs_files[@]} -eq 0 ]]; then
    warn "No top-level scripts/*.sh files found for guardrail checks"
  else
    run_scripts_guardrails_check "${scripts_abs_files[@]}"
  fi

  run_forbidden_pipeline_check "${shell_rel_files[@]}"
fi
