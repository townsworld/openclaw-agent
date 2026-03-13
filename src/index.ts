import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { runAgent } from "./runner.js";
import { formatRunResult } from "./formatter.js";
import { ensureShutdownHook, setMaxConcurrent } from "./process-registry.js";
import { resolveAgentBinary } from "./cursor-runner.js";
import { detectProxyEnv } from "./claude-runner.js";
import { detectCodexEnv } from "./codex-runner.js";
import { createCodeAgentTool } from "./tool.js";
import type { CliType, OpenclawAgentConfig, ParsedCommand, ResolvedBinary } from "./types.js";

const PLUGIN_ID = "openclaw-agent";

const DEFAULT_TIMEOUT_SEC = 600;
const DEFAULT_NO_OUTPUT_TIMEOUT_SEC = 120;
const DEFAULT_ENABLE_MCP = true;
const DEFAULT_MODE = "agent" as const;

function detectCliPath(name: string, candidates: string[]): string | null {
  try {
    const result = spawnSync("which", [name], { encoding: "utf-8", timeout: 5000 });
    const first = (result.stdout ?? "").trim().split("\n")[0]?.trim();
    if (first && existsSync(first)) return first;
  } catch { /* ignore */ }

  const home = process.env.HOME || "";
  for (const rel of candidates) {
    const p = resolve(home, rel);
    if (existsSync(p)) return p;
  }
  return null;
}

function detectAgentPath(): string | null {
  return detectCliPath("agent", [".cursor/bin/agent", ".local/bin/agent"]);
}

function detectClaudePath(): string | null {
  return detectCliPath("claude", [".local/bin/claude", ".nvm/versions/node/current/bin/claude"]);
}

function detectCodexPath(): string | null {
  return detectCliPath("codex", [".local/bin/codex", ".nvm/versions/node/current/bin/codex"]);
}

export function parseCommandArgs(args: string, cliName: string): ParsedCommand | { error: string } {
  if (!args?.trim()) {
    return {
      error: `Usage: /${cliName} <project> <prompt>\n\nOptions:\n  --continue          Continue previous session\n  --resume <chatId>   Resume a specific session\n  --mode <mode>       Set mode (agent|ask|plan)`,
    };
  }

  const tokens = tokenize(args.trim());
  if (tokens.length === 0) return { error: "Missing project parameter" };

  const project = tokens[0]!;
  let mode: "agent" | "ask" | "plan" = DEFAULT_MODE;
  let continueSession = false;
  let resumeSessionId: string | undefined;
  const promptParts: string[] = [];

  let i = 1;
  while (i < tokens.length) {
    const token = tokens[i]!;
    if (token === "--continue") {
      continueSession = true;
      i++;
    } else if (token === "--resume") {
      i++;
      if (i >= tokens.length) return { error: "--resume requires a chatId" };
      resumeSessionId = tokens[i]!;
      i++;
    } else if (token === "--mode") {
      i++;
      if (i >= tokens.length) return { error: "--mode requires a mode (agent|ask|plan)" };
      const m = tokens[i]! as "agent" | "ask" | "plan";
      if (!["agent", "ask", "plan"].includes(m)) {
        return { error: `Unsupported mode: ${m}, available: agent, ask, plan` };
      }
      mode = m;
      i++;
    } else {
      promptParts.push(tokens.slice(i).join(" "));
      break;
    }
  }

  const prompt = promptParts.join(" ").trim();
  if (!prompt) return { error: "Missing prompt parameter" };

  return { project, prompt, mode, continueSession, resumeSessionId };
}

export function tokenize(input: string): string[] {
  const tokens: string[] = [];
  let current = "";
  let inQuote: string | null = null;

  for (const ch of input) {
    if (inQuote) {
      if (ch === inQuote) inQuote = null;
      else current += ch;
    } else if (ch === '"' || ch === "'") {
      inQuote = ch;
    } else if (ch === " " || ch === "\t") {
      if (current) { tokens.push(current); current = ""; }
    } else {
      current += ch;
    }
  }
  if (current) tokens.push(current);
  return tokens;
}

export function resolveProjectPath(
  projectKey: string,
  projects: Record<string, string>,
): string | null {
  if (projects[projectKey]) return projects[projectKey]!;

  const lowerKey = projectKey.toLowerCase();
  for (const [name, path] of Object.entries(projects)) {
    if (name.toLowerCase() === lowerKey) return path;
  }

  if (existsSync(projectKey)) return projectKey;
  return null;
}

export default {
  id: PLUGIN_ID,
  configSchema: { type: "object" as const },

  register(api: any) {
    const cfg: OpenclawAgentConfig = api.pluginConfig ?? {};
    console.log(`[${PLUGIN_ID}] pluginConfig:`, JSON.stringify(cfg));

    const projects = cfg.projects ?? {};
    const projectNames = Object.keys(projects);
    const projectListStr = projectNames.length > 0
      ? `Available projects: ${projectNames.join(", ")}`
      : "No pre-configured projects, provide a full path";

    const timeoutSec = cfg.defaultTimeoutSec ?? DEFAULT_TIMEOUT_SEC;
    const noOutputTimeoutSec = cfg.noOutputTimeoutSec ?? DEFAULT_NO_OUTPUT_TIMEOUT_SEC;

    if (cfg.maxConcurrent) setMaxConcurrent(cfg.maxConcurrent);
    ensureShutdownHook();

    // ── Cursor CLI setup ──
    const cursorCfg = cfg.cursor ?? {};
    const agentPath = cursorCfg.agentPath || detectAgentPath();
    let resolvedBinary: ResolvedBinary | undefined;

    if (agentPath) {
      if (cursorCfg.agentNodeBin && cursorCfg.agentEntryScript
        && existsSync(cursorCfg.agentNodeBin) && existsSync(cursorCfg.agentEntryScript)) {
        resolvedBinary = { nodeBin: cursorCfg.agentNodeBin, entryScript: cursorCfg.agentEntryScript };
      } else {
        resolvedBinary = resolveAgentBinary(agentPath) ?? undefined;
      }
    }

    if (agentPath) {
      api.registerCommand({
        name: "cursor",
        description: `Invoke Cursor Agent for code analysis and modification. ${projectListStr}`,
        acceptsArgs: true,
        requireAuth: false,

        async handler(ctx: any) {
          const parsed = parseCommandArgs(ctx.args ?? "", "cursor");
          if ("error" in parsed) return { text: parsed.error };

          const projectPath = resolveProjectPath(parsed.project, projects);
          if (!projectPath) {
            return { text: `Project not found: ${parsed.project}\n${projectListStr}` };
          }

          const result = await runAgent({
            cliType: "cursor",
            cliPath: agentPath,
            resolvedBinary,
            projectPath,
            prompt: parsed.prompt,
            mode: parsed.mode,
            timeoutSec,
            noOutputTimeoutSec,
            enableMcp: cursorCfg.enableMcp ?? DEFAULT_ENABLE_MCP,
            model: cursorCfg.model,
            prefixArgs: cursorCfg.prefixArgs,
            continueSession: parsed.continueSession,
            resumeSessionId: parsed.resumeSessionId,
          });

          const messages = formatRunResult(result);
          return { text: messages.join("\n\n---\n\n") };
        },
      });
      console.log(`[${PLUGIN_ID}] registered /cursor command (agent: ${agentPath})`);
    } else {
      console.warn(`[${PLUGIN_ID}] Cursor Agent CLI not found, /cursor command disabled`);
    }

    // ── Claude Code CLI setup ──
    const claudeCfg = cfg.claude ?? {};
    const claudePath = claudeCfg.claudePath || detectClaudePath();
    const proxyEnv = detectProxyEnv(claudeCfg);

    if (claudePath) {
      if (proxyEnv) {
        console.log(`[${PLUGIN_ID}] Claude Code: proxy mode (ANTHROPIC_BASE_URL=${proxyEnv.ANTHROPIC_BASE_URL})`);
      } else {
        console.log(`[${PLUGIN_ID}] Claude Code: standard login mode`);
      }

      api.registerCommand({
        name: "claude",
        description: `Invoke Claude Code for code analysis and modification. ${projectListStr}`,
        acceptsArgs: true,
        requireAuth: false,

        async handler(ctx: any) {
          const parsed = parseCommandArgs(ctx.args ?? "", "claude");
          if ("error" in parsed) return { text: parsed.error };

          const projectPath = resolveProjectPath(parsed.project, projects);
          if (!projectPath) {
            return { text: `Project not found: ${parsed.project}\n${projectListStr}` };
          }

          const result = await runAgent({
            cliType: "claude",
            cliPath: claudePath,
            projectPath,
            prompt: parsed.prompt,
            mode: parsed.mode,
            timeoutSec,
            noOutputTimeoutSec,
            model: claudeCfg.model,
            extraEnv: proxyEnv ?? undefined,
            continueSession: parsed.continueSession,
            resumeSessionId: parsed.resumeSessionId,
          });

          const messages = formatRunResult(result);
          return { text: messages.join("\n\n---\n\n") };
        },
      });
      console.log(`[${PLUGIN_ID}] registered /claude command (claude: ${claudePath})`);
    } else {
      console.warn(`[${PLUGIN_ID}] Claude Code CLI not found, /claude command disabled`);
    }

    // ── Codex CLI setup ──
    const codexCfg = cfg.codex ?? {};
    const codexPath = codexCfg.codexPath || detectCodexPath();
    const codexEnv = detectCodexEnv(codexCfg);

    if (codexPath) {
      if (codexEnv) {
        console.log(`[${PLUGIN_ID}] Codex: API key configured`);
      } else {
        console.log(`[${PLUGIN_ID}] Codex: using default auth (codex login)`);
      }

      api.registerCommand({
        name: "codex",
        description: `Invoke OpenAI Codex for code analysis and modification. ${projectListStr}`,
        acceptsArgs: true,
        requireAuth: false,

        async handler(ctx: any) {
          const parsed = parseCommandArgs(ctx.args ?? "", "codex");
          if ("error" in parsed) return { text: parsed.error };

          const projectPath = resolveProjectPath(parsed.project, projects);
          if (!projectPath) {
            return { text: `Project not found: ${parsed.project}\n${projectListStr}` };
          }

          const result = await runAgent({
            cliType: "codex",
            cliPath: codexPath,
            projectPath,
            prompt: parsed.prompt,
            mode: parsed.mode,
            timeoutSec,
            noOutputTimeoutSec,
            model: codexCfg.model,
            extraEnv: codexEnv ?? undefined,
            continueSession: parsed.continueSession,
            resumeSessionId: parsed.resumeSessionId,
          });

          const messages = formatRunResult(result);
          return { text: messages.join("\n\n---\n\n") };
        },
      });
      console.log(`[${PLUGIN_ID}] registered /codex command (codex: ${codexPath})`);
    } else {
      console.warn(`[${PLUGIN_ID}] Codex CLI not found, /codex command disabled`);
    }

    // ── Agent Tool registration ──
    const availableEngines: CliType[] = [];
    if (agentPath) availableEngines.push("cursor");
    if (claudePath) availableEngines.push("claude");
    if (codexPath) availableEngines.push("codex");

    if (cfg.enableAgentTool !== false && projectNames.length > 0 && availableEngines.length > 0) {
      const defaultEngine: CliType = cfg.defaultEngine
        ?? (availableEngines.includes("cursor") ? "cursor" : availableEngines[0]!);

      api.registerTool(
        createCodeAgentTool({
          projects,
          cfg,
          availableEngines,
          defaultEngine,
          cursorPath: agentPath ?? undefined,
          claudePath: claudePath ?? undefined,
          codexPath: codexPath ?? undefined,
          resolvedBinary,
          proxyEnv,
          codexEnv,
        }),
        { name: "code_agent" },
      );
      console.log(`[${PLUGIN_ID}] registered code_agent tool (engines: ${availableEngines.join(", ")}, default: ${defaultEngine})`);
    }
  },
};
