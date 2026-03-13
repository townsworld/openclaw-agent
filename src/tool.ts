import { runAgent } from "./runner.js";
import { formatRunResult } from "./formatter.js";
import { resolveProjectPath } from "./index.js";
import type { CliType, OpenclawAgentConfig, ResolvedBinary } from "./types.js";

const RESULT_INSTRUCTION = [
  "",
  "─".repeat(40),
  "请保持代码片段、diff、错误日志等技术内容的完整性，不要截断或改写。",
  "可以在输出前后添加简要说明帮助用户理解。",
  "─".repeat(40),
].join("\n");

interface ToolContext {
  config?: Record<string, unknown>;
  workspaceDir?: string;
  agentDir?: string;
  agentId?: string;
  sessionKey?: string;
  messageChannel?: string;
  agentAccountId?: string;
  sandboxed?: boolean;
}

interface ToolResult {
  content: Array<{ type: string; text: string }>;
  details?: Record<string, unknown>;
}

export function createCodeAgentTool(params: {
  projects: Record<string, string>;
  cfg: OpenclawAgentConfig;
  availableEngines: CliType[];
  defaultEngine: CliType;
  cursorPath?: string;
  claudePath?: string;
  codexPath?: string;
  resolvedBinary?: ResolvedBinary;
  proxyEnv?: Record<string, string> | null;
  codexEnv?: Record<string, string> | null;
}) {
  const projectNames = Object.keys(params.projects);
  const projectListStr = projectNames.join(", ");
  const engineListStr = params.availableEngines.join(", ");

  return (_ctx: ToolContext) => ({
    name: "code_agent",
    label: "Code Agent",
    description:
      `Invoke Cursor Agent, Claude Code, or Codex CLI to analyze or modify project code on the local machine. ` +
      `Use when the user asks to use cursor/claude/codex, or needs deep code analysis, debugging, or modification in a project. ` +
      `Available engines: ${engineListStr}. Default: ${params.defaultEngine}. ` +
      `Available projects: ${projectListStr}. ` +
      `Refer to the code-agent skill for detailed usage guidance.`,
    parameters: {
      type: "object" as const,
      properties: {
        project: {
          type: "string" as const,
          description: `Project name (one of: ${projectListStr}) or absolute path to project directory`,
        },
        prompt: {
          type: "string" as const,
          description: "Task description — be specific about what to analyze or change",
        },
        mode: {
          type: "string" as const,
          enum: ["agent", "ask", "plan"],
          description: "Execution mode: ask (read-only analysis, default), plan (generate plan), agent (can modify files)",
        },
        engine: {
          type: "string" as const,
          enum: params.availableEngines,
          description: `Which CLI engine to use. When user says "use cursor" set this to "cursor", "use claude" → "claude", "use codex" → "codex". Default: ${params.defaultEngine}.`,
        },
      },
      required: ["project", "prompt"],
    },

    async execute(
      _toolCallId: string,
      args: Record<string, unknown>,
      signal?: AbortSignal,
    ): Promise<ToolResult> {
      const project = String(args.project ?? "");
      const prompt = String(args.prompt ?? "");
      const mode = (args.mode as "agent" | "ask" | "plan") ?? "ask";
      const engine = (args.engine as CliType) ?? params.defaultEngine;

      if (!project || !prompt) {
        return {
          content: [{ type: "text", text: "Missing required parameters: project and prompt" }],
        };
      }

      if (!params.availableEngines.includes(engine)) {
        return {
          content: [{ type: "text", text: `Engine "${engine}" is not available. Available: ${engineListStr}` }],
        };
      }

      const projectPath = resolveProjectPath(project, params.projects);
      if (!projectPath) {
        return {
          content: [{ type: "text", text: `Project not found: ${project}. Available projects: ${projectListStr}` }],
        };
      }

      const cliPath = engine === "cursor" ? params.cursorPath!
        : engine === "claude" ? params.claudePath!
        : params.codexPath!;
      const cursorCfg = params.cfg.cursor ?? {};
      const claudeCfg = params.cfg.claude ?? {};
      const codexCfg = params.cfg.codex ?? {};
      const timeoutSec = params.cfg.defaultTimeoutSec ?? 600;
      const noOutputTimeoutSec = params.cfg.noOutputTimeoutSec ?? 120;

      const result = await runAgent({
        cliType: engine,
        cliPath,
        resolvedBinary: engine === "cursor" ? params.resolvedBinary : undefined,
        projectPath,
        prompt,
        mode,
        timeoutSec,
        noOutputTimeoutSec,
        enableMcp: engine === "cursor" ? (cursorCfg.enableMcp ?? true) : undefined,
        model: engine === "cursor" ? cursorCfg.model : engine === "claude" ? claudeCfg.model : codexCfg.model,
        prefixArgs: engine === "cursor" ? cursorCfg.prefixArgs : undefined,
        extraEnv: engine === "claude" ? (params.proxyEnv ?? undefined)
          : engine === "codex" ? (params.codexEnv ?? undefined)
          : undefined,
        signal,
      });

      const messages = formatRunResult(result);
      const combined = messages.join("\n\n---\n\n");

      return {
        content: [{
          type: "text",
          text: combined + RESULT_INSTRUCTION,
        }],
        details: {
          success: result.success,
          engine,
          sessionId: result.sessionId,
          sentDirectly: false,
        },
      };
    },
  });
}
