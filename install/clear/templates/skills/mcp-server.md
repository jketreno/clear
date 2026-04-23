---
name: mcp-server
description: "Scaffold an MCP server exposing CLEAR verify and autonomy-check tools"
mode: agent
---

# CLEAR MCP Server

> **What this skill does:** Scaffolds a minimal MCP (Model Context Protocol) server that
> exposes CLEAR's enforcement primitives — `verify-ci.sh` and `autonomy.yml` — as typed
> tool calls. Any MCP-compatible agent or orchestrator can then call CLEAR tools without
> needing bash access or CLEAR-specific prompt engineering.
>
> **When to use:** When running multi-agent pipelines, headless agents, or any workflow
> where you need CLEAR enforcement available as a structured tool rather than a bash script.
>
> **Output:** A `mcp/` directory containing a runnable MCP server + registration instructions.

---

## Context

CLEAR's two core enforcement primitives are:

1. `clear/verify-ci.sh` — runs all CI checks, exits non-zero on failure
2. `clear/autonomy.yml` — YAML file mapping file paths to autonomy levels

This skill exposes them as three MCP tools:

| Tool | Input | Output |
|------|-------|--------|
| `clear_verify` | (none) | `{status, passed[], failed[{check, output}], summary}` |
| `clear_check_autonomy` | `{path: string}` | `{path, matched_rule, level, reason}` |
| `clear_list_humans_only` | (none) | `{humans_only_paths: string[]}` |

---

## Instructions

When this skill is invoked, generate a CLEAR MCP server for the current project.

### Step 1: Detect the project runtime

Check for `package.json` → generate Node.js server.
Check for `pyproject.toml` or `requirements.txt` → generate Python server.
If both exist, ask the user which runtime to use.
If neither, default to Node.js.

### Step 2: Scaffold the server

**For Node.js** — create `mcp/clear-server.js`:

```javascript
#!/usr/bin/env node
// @generated — regenerate from clear/templates/skills/mcp-server.md, do not hand-edit
//
// CLEAR MCP Server
// Exposes CLEAR enforcement primitives as MCP tool calls.
// See docs/agentic.md for usage in multi-agent pipelines.

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { execSync } from 'child_process';
import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import yaml from 'js-yaml';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = resolve(__dirname, '..');

const server = new Server(
  { name: 'clear', version: '1.0.0' },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'clear_verify',
      description: 'Run clear/verify-ci.sh and return structured pass/fail results. Call this after any code generation before reporting work complete.',
      inputSchema: { type: 'object', properties: {}, required: [] }
    },
    {
      name: 'clear_check_autonomy',
      description: 'Look up the autonomy level for a file path in clear/autonomy.yml. Call this before modifying any file.',
      inputSchema: {
        type: 'object',
        properties: {
          path: { type: 'string', description: 'File path relative to project root' }
        },
        required: ['path']
      }
    },
    {
      name: 'clear_list_humans_only',
      description: 'List all humans-only paths from clear/autonomy.yml. Call this as a pre-flight check before delegating tasks to sub-agents.',
      inputSchema: { type: 'object', properties: {}, required: [] }
    }
  ]
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === 'clear_verify') {
    try {
      const output = execSync(`${PROJECT_ROOT}/clear/verify-ci.sh`, {
        cwd: PROJECT_ROOT,
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe']
      });
      return {
        content: [{ type: 'text', text: JSON.stringify({ status: 'passed', output, summary: 'All checks passed' }) }]
      };
    } catch (err) {
      const output = err.stdout + err.stderr;
      const failedChecks = (output.match(/❌ (.+)/g) || []).map(l => l.replace('❌ ', '').trim());
      return {
        content: [{ type: 'text', text: JSON.stringify({ status: 'failed', failed: failedChecks, output, summary: `${failedChecks.length} check(s) failed` }) }]
      };
    }
  }

  if (name === 'clear_check_autonomy') {
    const targetPath = args.path;
    const autonomyFile = readFileSync(`${PROJECT_ROOT}/clear/autonomy.yml`, 'utf8');
    const autonomy = yaml.load(autonomyFile);
    
    const modules = autonomy.modules || [];
    let matched = modules.find(m => m.path !== '*' && targetPath.startsWith(m.path));
    if (!matched) matched = modules.find(m => m.path === '*');
    
    return {
      content: [{
        type: 'text',
        text: JSON.stringify({
          path: targetPath,
          matched_rule: matched?.path || 'none',
          level: matched?.level || 'unknown',
          reason: matched?.reason || ''
        })
      }]
    };
  }

  if (name === 'clear_list_humans_only') {
    const autonomyFile = readFileSync(`${PROJECT_ROOT}/clear/autonomy.yml`, 'utf8');
    const autonomy = yaml.load(autonomyFile);
    const humansOnly = (autonomy.modules || [])
      .filter(m => m.level === 'humans-only')
      .map(m => m.path);
    return {
      content: [{ type: 'text', text: JSON.stringify({ humans_only_paths: humansOnly }) }]
    };
  }

  throw new Error(`Unknown tool: ${name}`);
});

const transport = new StdioServerTransport();
await server.connect(transport);
```

**For Python** — create `mcp/clear_server.py`:

```python
#!/usr/bin/env python3
# @generated — regenerate from clear/templates/skills/mcp-server.md, do not hand-edit
#
# CLEAR MCP Server
# Exposes CLEAR enforcement primitives as MCP tool calls.
# See docs/agentic.md for usage in multi-agent pipelines.

import subprocess
import json
import re
from pathlib import Path
import yaml
from mcp.server.fastmcp import FastMCP

PROJECT_ROOT = Path(__file__).parent.parent
VERIFY_SCRIPT = PROJECT_ROOT / "clear" / "verify-ci.sh"
AUTONOMY_FILE = PROJECT_ROOT / "clear" / "autonomy.yml"

mcp = FastMCP("clear")

def load_autonomy():
  if not AUTONOMY_FILE.exists():
    return {"error": "missing_autonomy", "message": "clear/autonomy.yml not found"}
  with open(AUTONOMY_FILE, encoding="utf-8") as f:
    return yaml.safe_load(f) or {}

@mcp.tool()
def clear_verify() -> str:
  if not VERIFY_SCRIPT.exists():
    return json.dumps({
      "status": "error",
      "error": "missing_verify_script",
      "summary": "clear/verify-ci.sh not found"
    })

  result = subprocess.run(
      [str(VERIFY_SCRIPT)],
            cwd=str(PROJECT_ROOT),
            capture_output=True,
            text=True
    )
  if result.returncode == 0:
    return json.dumps({
      "status": "passed", "output": result.stdout, "summary": "All checks passed"
    })

  output = result.stdout + result.stderr
  failed = re.findall(r"❌ (.+)", output)
  return json.dumps({
    "status": "failed", "failed": failed, "output": output,
    "summary": f"{len(failed)} check(s) failed"
  })

@mcp.tool()
def clear_check_autonomy(path: str) -> str:
  autonomy = load_autonomy()
  if "error" in autonomy:
    return json.dumps({"status": "error", **autonomy})

  modules = autonomy.get("modules", [])
  matched = next((m for m in modules if m.get("path") != "*" and path.startswith(m.get("path", ""))), None)
  if not matched:
    matched = next((m for m in modules if m.get("path") == "*"), None)
  return json.dumps({
    "path": path,
    "matched_rule": matched.get("path", "none") if matched else "none",
    "level": matched.get("level", "unknown") if matched else "unknown",
    "reason": matched.get("reason", "") if matched else ""
  })

@mcp.tool()
def clear_list_humans_only() -> str:
  autonomy = load_autonomy()
  if "error" in autonomy:
    return json.dumps({"status": "error", **autonomy})

  humans_only = [m.get("path") for m in autonomy.get("modules", []) if m.get("level") == "humans-only"]
  return json.dumps({"humans_only_paths": [p for p in humans_only if p]})

if __name__ == "__main__":
  mcp.run(transport="stdio")
```

### Step 3: Create package/dependency file

**For Node.js** — create `mcp/package.json`:

```json
{
  "name": "clear-mcp-server",
  "version": "1.0.0",
  "type": "module",
  "description": "CLEAR MCP server — exposes verify-ci.sh and autonomy.yml as MCP tools",
  "main": "clear-server.js",
  "scripts": {
    "start": "node clear-server.js"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "js-yaml": "^4.1.0"
  }
}
```

**For Python** — create `mcp/requirements.txt`:

```
mcp>=1.0.0
pyyaml>=6.0
```

### Step 4: Add to .gitignore

Append to `.gitignore`:
```
mcp/node_modules/
mcp/__pycache__/
```

### Step 5: Add run_check to verify-local.sh (optional)

If the user wants to verify the MCP server itself starts cleanly, add to `clear/verify-local.sh`:

```bash
if [[ -f "$PROJECT_ROOT/mcp/clear-server.js" ]]; then
  run_check "CLEAR MCP server syntax" "node --check $PROJECT_ROOT/mcp/clear-server.js 2>&1"
fi
```

### Step 6: Register in Claude Code and Cursor settings

After generating, output these registration instructions:

```
CLEAR MCP server created at mcp/. To register with Claude Code:

1. Install dependencies:
   # Node.js:
   cd mcp && npm install
   
   # Python:
   pip install -r mcp/requirements.txt

2. Add to .claude/settings.json (create if missing):
   {
     "mcpServers": {
       "clear": {
         "command": "node",        // or "python"
         "args": ["./mcp/clear-server.js"]   // or ["./mcp/clear_server.py"]
       }
     }
   }

3. Add to .cursor/mcp.json (create if missing):
   {
     "mcpServers": {
       "clear": {
         "command": "node",        // or "python"
         "args": ["./mcp/clear-server.js"]   // or ["./mcp/clear_server.py"]
       }
     }
   }

4. Restart Claude Code / Cursor. Tools will be available as:
   - mcp__clear__clear_verify
   - mcp__clear__clear_check_autonomy
   - mcp__clear__clear_list_humans_only

See clear/docs/agentic.md for multi-agent usage patterns.
```

---

## Verification

After scaffolding, verify the server starts:

```bash
# Node.js:
cd mcp && npm install && echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | node clear-server.js

# Python:
pip install -r mcp/requirements.txt && echo '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | python mcp/clear_server.py
```

Expected output: a JSON response listing the three CLEAR tools.

Passing tool-call validation example:

```bash
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"clear_verify","arguments":{}}}' | node mcp/clear-server.js
```

Expected output: JSON containing `"status":"passed"` or `"status":"failed"` with structured fields.
