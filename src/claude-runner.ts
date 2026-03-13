import type { ClaudeConfig, RunOptions } from "./types.js";

/**
 * Detect proxy env: process.env first, then fall back to plugin config.
 * This ensures LaunchAgent (no shell env) can still use proxy mode
 * via openclaw.json settings.
 */
export function detectProxyEnv(cfg?: ClaudeConfig): Record<string, string> | null {
  const baseUrl = process.env.ANTHROPIC_BASE_URL || cfg?.anthropicBaseUrl;
  const authToken = process.env.ANTHROPIC_AUTH_TOKEN || cfg?.anthropicAuthToken;
  if (baseUrl && authToken) {
    return { ANTHROPIC_BASE_URL: baseUrl, ANTHROPIC_AUTH_TOKEN: authToken };
  }
  return null;
}

/**
 * Build CLI args for Claude Code.
 *
 * Claude Code uses --permission-mode instead of --mode:
 *   ask   → (no flag, -p is read-only by default)
 *   plan  → --permission-mode plan
 *   agent → --permission-mode bypassPermissions (non-interactive, no confirmation)
 */
export function buildClaudeArgs(opts: RunOptions): { cmd: string; args: string[]; extraEnv: Record<string, string> } {
  const cliArgs: string[] = [];

  cliArgs.push("-p", "--output-format", "stream-json", "--verbose");

  if (opts.resumeSessionId) {
    cliArgs.push("--resume", opts.resumeSessionId);
  } else if (opts.continueSession) {
    cliArgs.push("--continue");
  }

  if (opts.mode === "plan") {
    cliArgs.push("--permission-mode", "plan");
  } else if (opts.mode === "agent") {
    cliArgs.push("--permission-mode", "bypassPermissions");
  }
  // ask mode: no extra flag needed, -p is read-only by default

  if (opts.model) {
    cliArgs.push("--model", opts.model);
  }

  cliArgs.push(opts.prompt);

  const proxyEnv = opts.extraEnv ?? detectProxyEnv() ?? {};

  return { cmd: opts.cliPath, args: cliArgs, extraEnv: proxyEnv };
}
