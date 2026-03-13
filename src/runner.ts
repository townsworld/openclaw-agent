import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { createInterface } from "node:readline";
import { buildCursorArgs } from "./cursor-runner.js";
import { buildClaudeArgs } from "./claude-runner.js";
import { buildCodexArgs } from "./codex-runner.js";
import { parseStreamLine, extractToolName, extractToolArgs, extractToolResult } from "./parser.js";
import * as registry from "./process-registry.js";
import type {
  RunOptions,
  RunResult,
  AssistantEvent,
  ResultEvent,
  ToolCallEvent,
  SystemInitEvent,
  CollectedEvent,
} from "./types.js";

function buildCommand(opts: RunOptions): { cmd: string; args: string[]; extraEnv: Record<string, string> } {
  if (opts.cliType === "claude") {
    return buildClaudeArgs(opts);
  }
  if (opts.cliType === "codex") {
    return buildCodexArgs(opts);
  }
  const { cmd, args } = buildCursorArgs(opts);
  return { cmd, args, extraEnv: {} };
}

export async function runAgent(opts: RunOptions): Promise<RunResult> {
  if (registry.isFull()) {
    return {
      success: false,
      cliType: opts.cliType,
      resultText: `Concurrency limit reached (${registry.getActiveCount()}), please try again later`,
      durationMs: 0,
      toolCallCount: 0,
      error: "max concurrency reached",
      events: [],
    };
  }

  const runId = opts.runId ?? randomUUID();
  const startTime = Date.now();
  const { cmd, args, extraEnv } = buildCommand(opts);

  console.log(`[openclaw-agent] spawning: ${cmd} ${args.join(" ")} (cwd: ${opts.projectPath})`);

  const proc = spawn(cmd, args, {
    cwd: opts.projectPath,
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, ...extraEnv },
    detached: true,
  });
  proc.unref();

  // Capture stderr for diagnostics
  let stderrData = "";
  proc.stderr?.on("data", (chunk: Buffer) => {
    stderrData += chunk.toString();
  });

  registry.register(runId, { proc, projectPath: opts.projectPath, startTime });

  let sessionId: string | undefined;
  let resultText = "";
  let toolCallCount = 0;
  let completed = false;
  let error: string | undefined;
  let usage: ResultEvent["usage"];
  let lastOutputTime = Date.now();
  const events: CollectedEvent[] = [];

  const terminateProcess = () => {
    if (proc.exitCode !== null || proc.killed) return;
    registry.killWithGrace(proc);
  };

  const totalTimeout = setTimeout(() => {
    if (!completed) {
      error = `total timeout (${opts.timeoutSec}s)`;
      terminateProcess();
    }
  }, opts.timeoutSec * 1000);

  const noOutputCheck = setInterval(() => {
    if (Date.now() - lastOutputTime > opts.noOutputTimeoutSec * 1000) {
      if (!completed) {
        error = `no output timeout (${opts.noOutputTimeoutSec}s)`;
        terminateProcess();
      }
    }
  }, 5000);

  const onAbort = () => {
    if (!completed) {
      error = "aborted";
      terminateProcess();
    }
  };
  opts.signal?.addEventListener("abort", onAbort, { once: true });

  return new Promise<RunResult>((resolve) => {
    const rl = createInterface({ input: proc.stdout!, crlfDelay: Infinity });

    rl.on("line", (line) => {
      lastOutputTime = Date.now();
      const event = parseStreamLine(line);
      if (!event) return;

      if (opts.cliType === "codex") {
        handleCodexEvent(event as Record<string, unknown>);
      } else {
        handleStreamJsonEvent(event);
      }
    });

    function handleStreamJsonEvent(event: AgentStreamEvent) {
      switch (event.type) {
        case "system":
          if (event.subtype === "init") {
            sessionId = (event as SystemInitEvent).session_id;
          }
          break;

        case "user": {
          const ue = event as { message?: { content?: Array<{ text?: string }> } };
          const text = ue.message?.content?.[0]?.text;
          if (text) events.push({ type: "user", text, timestamp: event.timestamp_ms });
          break;
        }

        case "assistant": {
          const ae = event as AssistantEvent;
          const text = ae.message?.content?.[0]?.text;
          if (text) events.push({ type: "assistant", text, timestamp: event.timestamp_ms });
          break;
        }

        case "tool_call": {
          const tc = event as ToolCallEvent;
          if (tc.subtype === "started") {
            toolCallCount++;
            events.push({
              type: "tool_start",
              toolName: extractToolName(tc),
              toolArgs: extractToolArgs(tc),
              timestamp: event.timestamp_ms,
            });
          } else if (tc.subtype === "completed") {
            events.push({
              type: "tool_end",
              toolName: extractToolName(tc),
              toolResult: extractToolResult(tc),
              timestamp: event.timestamp_ms,
            });
          }
          break;
        }

        case "result": {
          const re = event as ResultEvent;
          resultText = re.result ?? "";
          usage = re.usage;
          completed = true;
          events.push({ type: "result", resultData: re, timestamp: event.timestamp_ms });
          break;
        }
      }
    }

    function handleCodexEvent(ev: Record<string, unknown>) {
      const type = ev.type as string;
      if (type === "thread.started") {
        sessionId = ev.thread_id as string;
      } else if (type === "item.completed") {
        const item = ev.item as Record<string, unknown> | undefined;
        if (!item) return;
        const itemType = item.type as string;
        if (itemType === "agent_message") {
          const text = item.text as string;
          if (text) {
            resultText = text;
            events.push({ type: "assistant", text, timestamp: Date.now() });
          }
        } else if (itemType === "command_execution") {
          toolCallCount++;
          const cmd = (item.command as string) ?? "";
          const shortCmd = cmd.length > 40 ? cmd.slice(0, 40) + "..." : cmd;
          events.push({ type: "tool_start", toolName: "shell", toolArgs: shortCmd, timestamp: Date.now() });
          const output = (item.output as string) ?? "";
          if (output) {
            events.push({ type: "tool_end", toolName: "shell", toolResult: output.slice(0, 2000), timestamp: Date.now() });
          }
        } else if (itemType === "file_change") {
          toolCallCount++;
          const filename = (item.filename as string) ?? "file";
          events.push({ type: "tool_start", toolName: "edit", toolArgs: filename, timestamp: Date.now() });
          events.push({ type: "tool_end", toolName: "edit", toolResult: `Modified: ${filename}`, timestamp: Date.now() });
        }
      } else if (type === "turn.completed") {
        completed = true;
        const u = ev.usage as Record<string, number> | undefined;
        if (u) {
          usage = {
            inputTokens: u.input_tokens ?? 0,
            outputTokens: u.output_tokens ?? 0,
            cacheReadTokens: u.cached_input_tokens,
          };
        }
        events.push({ type: "result", timestamp: Date.now() });
      } else if (type === "error") {
        error = (ev.message as string) ?? "codex error";
      }
    }

    let cleaned = false;
    const cleanup = (exitCode?: number | null) => {
      if (cleaned) return;
      cleaned = true;

      clearTimeout(totalTimeout);
      clearInterval(noOutputCheck);
      opts.signal?.removeEventListener("abort", onAbort);
      registry.unregister(runId);

      if (proc.exitCode === null && !proc.killed) {
        registry.killWithGrace(proc);
      }

      const durationMs = Date.now() - startTime;
      const label = opts.cliType === "cursor" ? "Cursor Agent" : opts.cliType === "claude" ? "Claude Code" : "Codex";

      if (stderrData.trim()) {
        console.error(`[openclaw-agent] ${label} stderr: ${stderrData.trim()}`);
      }
      if (exitCode !== 0 && exitCode !== null) {
        console.error(`[openclaw-agent] ${label} exited with code ${exitCode}`);
      }

      const errorDetail = error
        ? `${label} execution failed: ${error}`
        : !completed && stderrData.trim()
          ? `${label} failed: ${stderrData.trim().slice(0, 500)}`
          : !completed
            ? "No analysis result obtained"
            : "";

      resolve({
        success: !error && completed,
        cliType: opts.cliType,
        resultText: resultText || errorDetail,
        sessionId,
        durationMs,
        toolCallCount,
        error: error || (!completed ? stderrData.trim().slice(0, 500) || "process exited unexpectedly" : undefined),
        usage,
        events,
      });
    };

    proc.on("close", (code) => cleanup(code));
    proc.on("error", (err) => {
      error = err.message;
      cleanup();
    });
  });
}
