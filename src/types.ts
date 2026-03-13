/** Resolved binary info for Cursor Agent CLI */
export interface ResolvedBinary {
  nodeBin: string;
  entryScript: string;
}

/** Which CLI backend to use */
export type CliType = "cursor" | "claude" | "codex";

/** Shared plugin configuration */
export interface PluginConfig {
  projects?: Record<string, string>;
  defaultTimeoutSec?: number;
  noOutputTimeoutSec?: number;
  maxConcurrent?: number;
  enableAgentTool?: boolean;
}

/** Cursor-specific config */
export interface CursorConfig extends PluginConfig {
  agentPath?: string;
  agentNodeBin?: string;
  agentEntryScript?: string;
  model?: string;
  enableMcp?: boolean;
  prefixArgs?: string[];
}

/** Claude Code-specific config */
export interface ClaudeConfig extends PluginConfig {
  claudePath?: string;
  model?: string;
  anthropicBaseUrl?: string;
  anthropicAuthToken?: string;
}

/** Codex-specific config */
export interface CodexConfig extends PluginConfig {
  codexPath?: string;
  model?: string;
  openaiApiKey?: string;
}

/** Top-level plugin config */
export interface OpenclawAgentConfig {
  projects?: Record<string, string>;
  defaultTimeoutSec?: number;
  noOutputTimeoutSec?: number;
  maxConcurrent?: number;
  enableAgentTool?: boolean;
  defaultEngine?: CliType;
  cursor?: CursorConfig;
  claude?: ClaudeConfig;
  codex?: CodexConfig;
}

/** Base stream event */
export interface StreamEvent {
  type: string;
  subtype?: string;
  session_id?: string;
  model_call_id?: string;
  timestamp_ms?: number;
}

export interface SystemInitEvent extends StreamEvent {
  type: "system";
  subtype: "init";
  model: string;
  cwd: string;
  session_id: string;
}

export interface AssistantEvent extends StreamEvent {
  type: "assistant";
  message: {
    role: "assistant";
    content: Array<{ type: "text"; text: string }>;
  };
}

export interface ToolCallEvent extends StreamEvent {
  type: "tool_call";
  subtype: "started" | "completed";
  call_id: string;
  tool_call: Record<string, unknown>;
}

export interface ResultEvent extends StreamEvent {
  type: "result";
  subtype: "success" | "error";
  result: string;
  duration_ms: number;
  is_error: boolean;
  usage?: {
    inputTokens: number;
    outputTokens: number;
    cacheReadTokens?: number;
    cacheWriteTokens?: number;
  };
}

export interface UserEvent extends StreamEvent {
  type: "user";
  message: {
    role: "user";
    content: Array<{ type: "text"; text: string }>;
  };
}

export type AgentStreamEvent =
  | SystemInitEvent
  | AssistantEvent
  | ToolCallEvent
  | ResultEvent
  | UserEvent
  | StreamEvent;

export interface CollectedEvent {
  type: "assistant" | "tool_start" | "tool_end" | "result" | "user";
  timestamp?: number;
  text?: string;
  toolName?: string;
  toolArgs?: string;
  toolResult?: string;
  resultData?: ResultEvent;
}

/** Common run options for both CLIs */
export interface RunOptions {
  cliType: CliType;
  cliPath: string;
  resolvedBinary?: ResolvedBinary;
  projectPath: string;
  prompt: string;
  mode: "agent" | "ask" | "plan";
  timeoutSec: number;
  noOutputTimeoutSec: number;
  enableMcp?: boolean;
  model?: string;
  signal?: AbortSignal;
  continueSession?: boolean;
  resumeSessionId?: string;
  runId?: string;
  prefixArgs?: string[];
  /** Extra env vars to inject into the child process (e.g. ANTHROPIC_BASE_URL) */
  extraEnv?: Record<string, string>;
}

export interface RunResult {
  success: boolean;
  cliType: CliType;
  resultText: string;
  sessionId?: string;
  durationMs: number;
  toolCallCount: number;
  error?: string;
  usage?: ResultEvent["usage"];
  events: CollectedEvent[];
}

export interface ParsedCommand {
  project: string;
  prompt: string;
  mode: "agent" | "ask" | "plan";
  continueSession?: boolean;
  resumeSessionId?: string;
}
