#!/usr/bin/env bash
# =============================================================================
# Render Mermaid diagram assets for docs and social publishing.
#
# Usage:
#   ./scripts/render-mermaid-assets.sh
#
# Outputs:
#   assets/publish/readme.rendered.md
#   assets/publish/readme.rendered-*.svg
#   assets/publish/linkedin/clear-overview-1200x627.png
#   assets/publish/linkedin/clear-overview-1080x1080.png
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PUBLISH_DIR="$PROJECT_ROOT/assets/publish"
LINKEDIN_DIR="$PUBLISH_DIR/linkedin"
DIAGRAMS_DIR="$PROJECT_ROOT/assets/diagrams"
README_PATH="$PROJECT_ROOT/README.md"
SOCIAL_SOURCE="$DIAGRAMS_DIR/clear-overview.mmd"

readonly SCRIPT_DIR
readonly PROJECT_ROOT
readonly PUBLISH_DIR
readonly LINKEDIN_DIR
readonly DIAGRAMS_DIR
readonly README_PATH
readonly SOCIAL_SOURCE

BEAUTIFUL_MERMAID_VERSION="1.1.3"
RESVG_VERSION="2.6.2"

usage() {
  cat <<'EOF'
Usage: ./scripts/render-mermaid-assets.sh

Renders Mermaid assets using beautiful-mermaid only.
EOF
}

require_file() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo "Error: required file not found: $file_path" >&2
    exit 1
  fi
}

require_tooling() {
  if ! command -v npx >/dev/null 2>&1; then
    echo "Error: npx is required. Install Node.js + npm first." >&2
    exit 1
  fi

  if ! command -v npm >/dev/null 2>&1; then
    echo "Error: npm is required. Install Node.js + npm first." >&2
    exit 1
  fi
}

run_mmdc() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap "rm -rf '$tmp_dir'" RETURN

  (
    cd "$tmp_dir"
    npm init -y >/dev/null 2>&1
    npm install "beautiful-mermaid@${BEAUTIFUL_MERMAID_VERSION}" "@resvg/resvg-js@${RESVG_VERSION}" >/dev/null 2>&1

    node --input-type=module - "$README_PATH" "$SOCIAL_SOURCE" "$PUBLISH_DIR" "$LINKEDIN_DIR" <<'NODE'
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { renderMermaidSVG } from "beautiful-mermaid";
import { Resvg } from "@resvg/resvg-js";

const readmePath = process.argv[2];
const socialPath = process.argv[3];
const publishDir = process.argv[4];
const linkedinDir = process.argv[5];

const theme = {
  bg: "#f8fafc",
  fg: "#0f172a",
  accent: "#2563eb",
  line: "#1d4ed8",
  muted: "#475569",
  surface: "#e2e8f0",
  border: "#2563eb",
  transparent: false,
};

function renderSvg(diagram) {
  return renderMermaidSVG(diagram, theme);
}

function renderPng(svg, outputPath, width, height) {
  const resvg = new Resvg(svg, {
    fitTo: { mode: "width", value: width },
    background: "white",
  });
  const png = resvg.render();
  const resized = png.asPng({
    width,
    height,
  });
  writeFileSync(outputPath, resized);
}

const readme = readFileSync(readmePath, "utf8");
let index = 0;
const renderedReadme = readme.replace(/```mermaid\n([\s\S]*?)```/g, (_full, block) => {
  index += 1;
  const fileName = `readme.rendered-${index}.svg`;
  const outPath = path.join(publishDir, fileName);
  const svg = renderSvg(block.trim());
  writeFileSync(outPath, svg, "utf8");
  return `![diagram](./${fileName})`;
});

writeFileSync(path.join(publishDir, "readme.rendered.md"), renderedReadme, "utf8");

const social = readFileSync(socialPath, "utf8");
const socialSvg = renderSvg(social);
writeFileSync(path.join(linkedinDir, "clear-overview.svg"), socialSvg, "utf8");
renderPng(socialSvg, path.join(linkedinDir, "clear-overview-1200x627.png"), 1200, 627);
renderPng(socialSvg, path.join(linkedinDir, "clear-overview-1080x1080.png"), 1080, 1080);
NODE
  )
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  if [[ "$#" -gt 0 ]]; then
    echo "Error: unexpected arguments: $*" >&2
    usage
    exit 1
  fi

  require_tooling
  require_file "$README_PATH"
  require_file "$SOCIAL_SOURCE"

  mkdir -p "$PUBLISH_DIR" "$LINKEDIN_DIR"

  echo "Using beautiful-mermaid version: $BEAUTIFUL_MERMAID_VERSION"
  run_mmdc

  echo "Rendered Mermaid assets to: $PUBLISH_DIR"
}

main "$@"
