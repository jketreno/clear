#!/usr/bin/env bash
# =============================================================================
# CLEAR setup-clear.sh — Interactive setup wizard
# =============================================================================
# Guides you through configuring CLEAR for an existing project.
# Run this once when adopting CLEAR in a new codebase.
#
# Usage:
#   ./scripts/setup-clear.sh               # configure current project
#   ./scripts/setup-clear.sh /path/to/proj  # configure a different project
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEAR_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Accept an explicit project root as the first argument (used by bootstrap-project.sh)
# so we always run the latest wizard from the CLEAR repo, not the target's stale copy.
if [[ -n "${1:-}" ]]; then
  PROJECT_ROOT="$(cd "$1" && pwd)"
else
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

supports_color() {
  [[ -z "${NO_COLOR:-}" ]] || return 1
  [[ "${TERM:-}" != "dumb" ]] || return 1

  if [[ -n "${FORCE_COLOR:-}" || -n "${CLICOLOR_FORCE:-}" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
    return 0
  fi

  [[ -t 1 ]] || return 1

  if command -v tput >/dev/null 2>&1; then
    local colors
    colors="$(tput colors 2>/dev/null || printf '0')"
    [[ "$colors" =~ ^[0-9]+$ ]] || return 1
    ((colors >= 8)) || return 1
  fi

  return 0
}

if supports_color; then
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  NC='\033[0m'
else
  GREEN=''
  YELLOW=''
  BLUE=''
  CYAN=''
  NC=''
fi

info() { echo -e "${BLUE}ℹ  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠  $1${NC}"; }

header() {
  echo ""
  echo -e "${BLUE}════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}════════════════════════════════════════════${NC}"
  echo ""
}

ask() {
  local question="$1"
  local default="${2:-}"
  local answer
  if [[ -n "$default" ]]; then
    printf "${CYAN}?  %s [%s]: ${NC}" "$question" "$default" >&2
  else
    printf "${CYAN}?  %s: ${NC}" "$question" >&2
  fi
  read -r answer
  echo "${answer:-$default}"
}

ask_yn() {
  local question="$1"
  local default="${2:-y}"
  local answer
  if [[ "$default" == "y" ]]; then
    printf "${CYAN}?  %s [Y/n]: ${NC}" "$question" >&2
  else
    printf "${CYAN}?  %s [y/N]: ${NC}" "$question" >&2
  fi
  read -r answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy] ]]
}

# ─── Skill helper ────────────────────────────────────────────────────────────

# get_skill_meta <file> <field>
# Returns the value of a YAML frontmatter field ("name", "description") from a
# skill .md file. Falls back to filename-derived name / "# CLEAR Skill:" heading
# for older skill files that have no frontmatter.
get_skill_meta() {
  local file="$1"
  local field="$2"
  local first_line
  first_line=$(head -1 "$file")
  if [[ "$first_line" == "---" ]]; then
    awk -v f="${field}:" '
      NR==1{next}
      /^---$/{exit}
      index($0,f)==1{
        val=substr($0,length(f)+1)
        sub(/^[[:space:]"'"'"']+/,"",val)
        sub(/[[:space:]"'"'"']+$/,"",val)
        print val; exit
      }
    ' "$file"
  elif [[ "$field" == "name" ]]; then
    basename "$file" .md
  else
    awk '/^# CLEAR Skill:/{sub(/^# CLEAR Skill: /,""); print; exit}' "$file"
  fi
}

# ─── Step 1: Project name ─────────────────────────────────────────────────────

header "CLEAR Setup — Step 1: Project Info"

PROJECT_NAME=$(ask "Project name" "$(basename "$PROJECT_ROOT")")
echo ""
info "Setting up CLEAR for: $PROJECT_NAME"

USE_AUTONOMY_SKILL=false

# ─── Step 2: Autonomy boundaries ──────────────────────────────────────────────

header "CLEAR Setup — Step 2: Autonomy Boundaries [L]"

echo "CLEAR's Limited principle requires you to define which modules AI can"
echo "modify freely vs which need human oversight."
echo ""
echo "Autonomy levels:"
echo "  full-autonomy  — AI can modify freely (e.g., generated code, utilities)"
echo "  supervised     — AI generates, human reviews before merging"
echo "  humans-only    — No AI generation (e.g., payment logic, auth core)"
echo ""

AUTONOMY_ENTRIES=""

add_autonomy_entry() {
  local path level reason
  printf "${CYAN}  Path (e.g., src/utils, src/payment) — leave blank to finish: ${NC}" >/dev/tty
  read -r path </dev/tty
  [[ -z "$path" ]] && return 1 # blank = done
  level=$(ask "  Level (full-autonomy / supervised / humans-only)" "supervised")
  reason=$(ask "  Reason (why this level?)" "")
  AUTONOMY_ENTRIES="${AUTONOMY_ENTRIES}
  - path: \"${path}\"
    level: ${level}
    reason: \"${reason}\""
  return 0
}

if ask_yn "Use autonomy-bootstrap skill to generate clear/autonomy.yml after setup?" "y"; then
  USE_AUTONOMY_SKILL=true
  mkdir -p "$PROJECT_ROOT/clear"
  if [[ -f "$PROJECT_ROOT/clear/autonomy.yml" ]]; then
    info "Keeping existing clear/autonomy.yml (will refine it with autonomy-bootstrap)."
  else
    cat >"$PROJECT_ROOT/clear/autonomy.yml" <<AUTONOMY_EOF
# =============================================================================
# CLEAR autonomy.yml — Module Autonomy Boundaries
# =============================================================================
# CLEAR Principle: [L] Limited — Define where AI works alone vs with humans
#
# Levels:
#   full-autonomy  — AI can read, modify, and regenerate freely
#   supervised     — AI generates code, but human must review before commit
#   humans-only    — AI must NOT generate code; flag for human attention
#
# AI Instructions: Before modifying any file, check this list. If the file
# falls under a 'humans-only' path, stop and alert the user. If 'supervised',
# generate but add a review reminder. If 'full-autonomy', proceed normally.
# =============================================================================

project: "${PROJECT_NAME}"

modules:

  # ── Default for uncategorized paths ──────────────────────────────────────
  - path: "*"
    level: supervised
    reason: "Default: untagged modules require human review"

# =============================================================================
# Reality Alignment — Sources of Truth
# =============================================================================
# Add project-specific concepts after bootstrap or generate them via the
# autonomy-bootstrap skill.

sources_of_truth:
AUTONOMY_EOF
    success "Created starter clear/autonomy.yml"
  fi
  info "Manual autonomy prompts skipped. Setup will install and guide autonomy-bootstrap usage."
else
  echo "Enter your autonomy boundaries below (one per prompt)."
  echo "Press ENTER on a blank path to skip — you can edit clear/autonomy.yml later."
  echo ""

  while true; do
    add_autonomy_entry || break
  done

  # Write autonomy.yml
  mkdir -p "$PROJECT_ROOT/clear"
  cat >"$PROJECT_ROOT/clear/autonomy.yml" <<AUTONOMY_EOF
# =============================================================================
# CLEAR autonomy.yml — Module Autonomy Boundaries
# =============================================================================
# CLEAR Principle: [L] Limited — Define where AI works alone vs with humans
#
# Levels:
#   full-autonomy  — AI can read, modify, and regenerate freely
#   supervised     — AI generates code, but human must review before commit
#   humans-only    — AI must NOT generate code; flag for human attention
#
# AI Instructions: Before modifying any file, check this list. If the file
# falls under a 'humans-only' path, stop and alert the user. If 'supervised',
# generate but add a review reminder. If 'full-autonomy', proceed normally.
# =============================================================================

project: "${PROJECT_NAME}"

modules:${AUTONOMY_ENTRIES}

  # ── Default for uncategorized paths ──────────────────────────────────────
  - path: "*"
    level: supervised
    reason: "Default: untagged modules require human review"
AUTONOMY_EOF

  success "Created clear/autonomy.yml"
fi

# ─── Step 3: Source of truth ──────────────────────────────────────────────────

header "CLEAR Setup — Step 3: Reality Alignment [R]"

if [[ "$USE_AUTONOMY_SKILL" == true ]]; then
  echo "The autonomy-bootstrap skill will gather project concepts and draft"
  echo "sources_of_truth entries with your team context."
  echo ""
  info "Skipping manual sources-of-truth prompts in setup wizard."
else
  echo "The Reality-Aligned principle requires declaring a single source of"
  echo "truth for each key domain concept. When systems disagree, what wins?"
  echo ""

  SOURCES_OF_TRUTH=""

  declare -a CONCEPTS=()
  declare -a SOURCES=()
  declare -a SYSTEMS=()

  add_source_of_truth() {
    local concept source system
    printf "${CYAN}  Domain concept (e.g., User, Order, Subscription) — leave blank to finish: ${NC}" >/dev/tty
    read -r concept </dev/tty
    [[ -z "$concept" ]] && return 1 # blank = done
    source=$(ask "  Source of truth (e.g., database schema, OAuth/IAM provider, protobuf)" "")
    system=$(ask "  System/file that defines it (e.g., idp.users, schema.prisma)" "")
    SOURCES_OF_TRUTH="${SOURCES_OF_TRUTH}
  - concept: \"${concept}\"
    source_of_truth: \"${source}\"
    defined_in: \"${system}\""
    return 0
  }

  echo "Declare sources of truth for key domain concepts."
  echo "Press ENTER on a blank concept to skip — you can edit clear/autonomy.yml later."
  echo ""

  while true; do
    add_source_of_truth || break
  done

  # Append sources of truth to autonomy.yml (always; empty block is harmless)
  cat >>"$PROJECT_ROOT/clear/autonomy.yml" <<REALITY_EOF

# =============================================================================
# Reality Alignment — Sources of Truth
# =============================================================================
# AI Instructions: When generating code that touches any of these concepts,
# derive from the declared source. Never invent a representation.
# If implementations conflict, the source_of_truth wins.

sources_of_truth:${SOURCES_OF_TRUTH}
REALITY_EOF

  if [[ -n "$SOURCES_OF_TRUTH" ]]; then
    success "Added sources of truth to clear/autonomy.yml"
  fi
fi

# ─── Step 4: verify-ci.sh ─────────────────────────────────────────────────────

header "CLEAR Setup — Step 4: CI Verification [C]"

echo "The Constrained principle requires a local verification script that"
echo "mirrors your CI/CD pipeline. scripts/verify-ci.sh is already provided"
echo "and auto-detects your project's build tools, linters, and test runners."
echo ""
echo "verify-ci.sh is CLEAR-owned (updated when you pull new CLEAR versions)."
echo "Your project-specific checks go in scripts/verify-local.sh."
echo ""

if ask_yn "Make scripts executable now?" "y"; then
  chmod +x "$PROJECT_ROOT/scripts/"*.sh 2>/dev/null || true
  success "Scripts are now executable"
fi

echo ""
info "Add custom checks to scripts/verify-local.sh (never overwritten by CLEAR):"
echo "  • Your linter (ESLint, Ruff, etc.)"
echo "  • Your test runner (Jest, pytest, go test)"
echo "  • Architecture tests (see templates/architecture-tests/ and templates/examples/architecture-tests/)"
echo "  • Code generation checks (proto, OpenAPI, etc.)"
echo ""
info "See verify-local.sh for examples using run_check"

# ─── Step 5: AI tool configuration ────────────────────────────────────────────

header "CLEAR Setup — Step 5: AI Tool Configuration"

echo "CLEAR works best when your AI tools know about the rules."
echo ""
echo "Already included in this project:"
echo "  • .github/copilot-instructions.md  — GitHub Copilot / VS Code"
echo "  • CLAUDE.md                        — Claude Code"
echo "  • .cursor/rules/                   — Cursor"
echo ""
echo "Next steps per tool:"
echo "  VS Code/Copilot: The .github/copilot-instructions.md is auto-read."
echo "  Claude Code:     The CLAUDE.md in project root is auto-read."
echo "  Cursor:          The .cursor/rules/*.mdc files are applied automatically."
echo ""
echo "See docs/ai-tools/ for detailed setup guides."

# ─── Step 6: Install skills ───────────────────────────────────────────────────

header "CLEAR Setup — Step 6: Install Skills [optional]"

SKILLS_DIR="$CLEAR_ROOT/templates/skills"
EXAMPLES_DIR="$CLEAR_ROOT/templates/examples/skills"
PROMPTS_DIR="$PROJECT_ROOT/.github/prompts"
INSTALLED_SKILLS=""

# Helper: present a list of skills and install selected ones
# Usage: install_skills_menu <label> <file_array_name> <name_array_name> <desc_array_name>
install_skills_from_arrays() {
  local label="$1"
  shift
  local -n _files=$1 _names=$2 _descs=$3

  if [[ ${#_files[@]} -eq 0 ]]; then
    return
  fi

  echo "$label (installed to .github/prompts/ for AI assistants: Cursor, Copilot Chat, Claude, etc.):"
  echo ""
  for _i in "${!_files[@]}"; do
    printf "  %d. %s\n" "$((_i + 1))" "${_names[$_i]}"
    printf "     %s\n" "${_descs[$_i]}"
    echo ""
  done

  printf "${CYAN}  Enter numbers to install (space-separated), 'all', or press ENTER to skip: ${NC}" >/dev/tty
  read -r _SELECTION </dev/tty
  echo ""

  if [[ -n "$_SELECTION" ]]; then
    local _TO_INSTALL=()
    if [[ "$_SELECTION" == "all" ]]; then
      for _i in "${!_files[@]}"; do
        _TO_INSTALL+=("$_i")
      done
    else
      for _token in $_SELECTION; do
        if [[ "$_token" =~ ^[0-9]+$ ]]; then
          local _idx=$((_token - 1))
          if [[ $_idx -ge 0 && $_idx -lt ${#_files[@]} ]]; then
            _TO_INSTALL+=("$_idx")
          else
            warn "No skill at position $_token — skipped"
          fi
        fi
      done
    fi

    if [[ ${#_TO_INSTALL[@]} -gt 0 ]]; then
      mkdir -p "$PROMPTS_DIR"
      for _idx in "${_TO_INSTALL[@]}"; do
        local _name="${_names[$_idx]}"
        cp "${_files[$_idx]}" "$PROMPTS_DIR/${_name}.prompt.md"
        success "Installed: .github/prompts/${_name}.prompt.md"
        INSTALLED_SKILLS="$INSTALLED_SKILLS $_name"
      done
    fi
  else
    info "Skipped"
  fi
}

# ── Generic skills (project-agnostic, work without customization)
SKILL_FILES=()
SKILL_NAMES=()
SKILL_DESCS=()
for _sf in "$SKILLS_DIR"/*.md; do
  [[ -f "$_sf" ]] || continue
  SKILL_FILES+=("$_sf")
  SKILL_NAMES+=("$(get_skill_meta "$_sf" "name")")
  SKILL_DESCS+=("$(get_skill_meta "$_sf" "description")")
done

if [[ ${#SKILL_FILES[@]} -gt 0 ]]; then
  install_skills_from_arrays "Generic skills" SKILL_FILES SKILL_NAMES SKILL_DESCS
else
  info "No generic skills found in $SKILLS_DIR"
fi

if [[ "$USE_AUTONOMY_SKILL" == true ]]; then
  if [[ ! -f "$PROMPTS_DIR/autonomy-bootstrap.prompt.md" ]]; then
    if [[ -f "$SKILLS_DIR/autonomy-bootstrap.md" ]]; then
      mkdir -p "$PROMPTS_DIR"
      cp "$SKILLS_DIR/autonomy-bootstrap.md" "$PROMPTS_DIR/autonomy-bootstrap.prompt.md"
      success "Installed: .github/prompts/autonomy-bootstrap.prompt.md"
      if [[ " $INSTALLED_SKILLS " != *" autonomy-bootstrap "* ]]; then
        INSTALLED_SKILLS="$INSTALLED_SKILLS autonomy-bootstrap"
      fi
    else
      warn "autonomy-bootstrap skill template not found: $SKILLS_DIR/autonomy-bootstrap.md"
    fi
  fi

  echo ""
  info "Next: open your AI assistant (Cursor, Copilot Chat, Claude, etc.)"
  info "and run /autonomy-bootstrap to generate project-specific autonomy rules."
  info "If slash commands are unavailable, open .github/prompts/autonomy-bootstrap.prompt.md"
  info "and paste it into chat."
fi

# ── Example skills (domain-specific, need customization)
EX_FILES=()
EX_NAMES=()
EX_DESCS=()
if [[ -d "$EXAMPLES_DIR" ]]; then
  for _sf in "$EXAMPLES_DIR"/*.md; do
    [[ -f "$_sf" ]] || continue
    _bn="$(basename "$_sf")"
    [[ "$_bn" == "README.md" ]] && continue
    EX_FILES+=("$_sf")
    EX_NAMES+=("$(get_skill_meta "$_sf" "name")")
    EX_DESCS+=("$(get_skill_meta "$_sf" "description")")
  done
fi

if [[ ${#EX_FILES[@]} -gt 0 ]]; then
  echo ""
  echo "Example skills are domain-specific illustrations that need customization."
  echo "Look for UPDATE: comments in each file after installing."
  echo ""
  install_skills_from_arrays "Example skills" EX_FILES EX_NAMES EX_DESCS
fi

# ─── Step 7: Extensions ──────────────────────────────────────────────────────

header "CLEAR Setup — Step 7: Extensions [optional]"

echo "CLEAR extensions add optional tool checks to verify-ci.sh."
echo "Extensions are disabled by default. When enabled, verify-ci.sh will"
echo "check that the tool is installed and run it as part of verification."
echo ""
echo "Available extensions:"
echo ""

EXTENSIONS_FILE="$PROJECT_ROOT/clear/extensions.yml"
if [[ -f "$EXTENSIONS_FILE" ]]; then
  # Parse extension names and descriptions from extensions.yml
  EXT_NAMES=()
  EXT_DESCS=()
  EXT_HINTS=()
  EXT_URLS=()
  local_name="" local_desc="" local_hint="" local_url=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.*) ]]; then
      if [[ -n "$local_name" ]]; then
        EXT_NAMES+=("$local_name")
        EXT_DESCS+=("$local_desc")
        EXT_HINTS+=("$local_hint")
        EXT_URLS+=("$local_url")
      fi
      local_name="${BASH_REMATCH[1]}"
      local_name="${local_name#\"}"
      local_name="${local_name%\"}"
      local_desc=""
      local_hint=""
      local_url=""
    elif [[ "$line" =~ ^[[:space:]]*description:[[:space:]]*(.*) ]]; then
      local_desc="${BASH_REMATCH[1]}"
      local_desc="${local_desc#\"}"
      local_desc="${local_desc%\"}"
    elif [[ "$line" =~ ^[[:space:]]*install_hint:[[:space:]]*(.*) ]]; then
      local_hint="${BASH_REMATCH[1]}"
      local_hint="${local_hint#\"}"
      local_hint="${local_hint%\"}"
    elif [[ "$line" =~ ^[[:space:]]*project_url:[[:space:]]*(.*) ]]; then
      local_url="${BASH_REMATCH[1]}"
      local_url="${local_url#\"}"
      local_url="${local_url%\"}"
    fi
  done <"$EXTENSIONS_FILE"
  # Capture the last one
  if [[ -n "$local_name" ]]; then
    EXT_NAMES+=("$local_name")
    EXT_DESCS+=("$local_desc")
    EXT_HINTS+=("$local_hint")
    EXT_URLS+=("$local_url")
  fi

  for _i in "${!EXT_NAMES[@]}"; do
    printf "  %d. %s — %s\n" "$((_i + 1))" "${EXT_NAMES[$_i]}" "${EXT_DESCS[$_i]}"
    printf "     Install: %s\n" "${EXT_HINTS[$_i]}"
    [[ -n "${EXT_URLS[$_i]}" ]] && printf "     Project: %s\n" "${EXT_URLS[$_i]}"
    echo ""
  done

  printf "${CYAN}  Enter numbers to enable (space-separated), 'all', or press ENTER to skip: ${NC}" >/dev/tty
  read -r EXT_SELECTION </dev/tty
  echo ""

  if [[ -n "$EXT_SELECTION" ]]; then
    ENABLE_EXTS=()
    if [[ "$EXT_SELECTION" == "all" ]]; then
      for _i in "${!EXT_NAMES[@]}"; do
        ENABLE_EXTS+=("${EXT_NAMES[$_i]}")
      done
    else
      for _token in $EXT_SELECTION; do
        if [[ "$_token" =~ ^[0-9]+$ ]]; then
          _idx=$((_token - 1))
          if [[ $_idx -ge 0 && $_idx -lt ${#EXT_NAMES[@]} ]]; then
            ENABLE_EXTS+=("${EXT_NAMES[$_idx]}")
          else
            warn "No extension at position $_token — skipped"
          fi
        fi
      done
    fi

    for _ext in "${ENABLE_EXTS[@]}"; do
      # Check if tool is available before enabling
      if command -v "$_ext" &>/dev/null; then
        # Toggle enabled: false → enabled: true in extensions.yml
        sed -i "/name:[[:space:]]*${_ext}/,/enabled:/{s/enabled:[[:space:]]*false/enabled: true/}" "$EXTENSIONS_FILE"
        success "Enabled extension: $_ext"
      else
        warn "$_ext is not installed. Enable anyway?"
        echo "  Install with: ${EXT_HINTS[$_i]:-check the extensions.yml for install instructions}"
        echo ""
        if ask_yn "  Enable $_ext without installing? (verify-ci.sh will remind you)" "n"; then
          sed -i "/name:[[:space:]]*${_ext}/,/enabled:/{s/enabled:[[:space:]]*false/enabled: true/}" "$EXTENSIONS_FILE"
          success "Enabled extension: $_ext (not yet installed — verify-ci.sh will show install instructions)"
        else
          info "Skipped $_ext — enable later by editing clear/extensions.yml"
        fi
      fi
    done
  else
    info "No extensions enabled — edit clear/extensions.yml later to enable"
  fi
else
  info "No extensions.yml found — extensions will be available after bootstrap"
fi

# ─── Step 8: First experiment ─────────────────────────────────────────────────

header "CLEAR Setup — Step 8: Your First Experiment"

echo "The fastest way to see CLEAR working is to pick ONE existing code"
echo "review comment that you write every PR."
echo ""
echo "Ask your AI:"
echo "  'Turn this code review rule into an architecture test:"
echo "   [YOUR MOST COMMON REVIEW COMMENT]'"
echo "  'Add it to scripts/verify-local.sh'"
echo ""
echo "See docs/getting-started.md for the full step-by-step guide."
echo "See templates/architecture-tests/ and templates/examples/architecture-tests/ for examples."

# ─── Summary ─────────────────────────────────────────────────────────────────

header "Setup Complete"

echo "Created/configured:"
echo "  ✅ clear/autonomy.yml          — autonomy boundaries"
echo "  ✅ scripts/verify-ci.sh        — CI enforcement script (CLEAR-owned)"
echo "  ✅ scripts/verify-local.sh     — project-specific checks (yours to edit)"
if [[ -n "$INSTALLED_SKILLS" ]]; then
  for _s in $INSTALLED_SKILLS; do
    echo "  ✅ .github/prompts/${_s}.prompt.md"
  done
fi
echo ""
echo "Next steps:"
echo "  1. Open your AI assistant (Cursor, Copilot Chat, Claude, etc.)"
echo "     and run the installed skill (for example: /autonomy-bootstrap)."
echo "     If slash commands are unavailable, open .github/prompts/*.prompt.md"
echo "     and paste the instructions into chat."
echo "  2. Review clear/autonomy.yml and adjust boundaries for your codebase"
echo "  3. Open scripts/verify-local.sh and add your project-specific checks"
echo "  4. Run ./scripts/verify-ci.sh to see which checks pass/fail today"
echo "  5. Read docs/getting-started.md for the full workflow"
echo ""
success "CLEAR is configured for: $PROJECT_NAME"
