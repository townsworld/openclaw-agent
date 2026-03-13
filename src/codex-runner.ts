import type { CodexConfig, RunOptions } from "./types.js";

/**
 * Detect OPENAI_API_KEY / CODEX_API_KEY from env or plugin config.
 */
export function detectCodexEnv(cfg?: CodexConfig): Record<string, string> | null {
  const apiKey = process.env.CODEX_API_KEY || process.env.OPENAI_API_KEY || cfg?.openaiApiKey;
  if (apiKey) {
    return { CODEX_API_KEY: apiKey };
  }
  return null;
}

/**
 * Build CLI args for Codex non-interactive mode (codex exec --json).
 *
 * Codex uses `codex exec` for non-interactive, with `--json` for JSONL streaming.
 * Mode mapping:
 *   ask   → --sandbox read-only
 *   plan  → --sandbox read-only
 *   agent → --full-auto (sandbox workspace-write + auto-approve)
 *
 * Codex session resume uses `codex exec resume --last` or `codex exec resume <id>`.
 */
export function buildCodexArgs(opts: RunOptions): { cmd: string; args: string[]; extraEnv: Record<string, string> } {
  const cliArgs: string[] = [];

  if (opts.resumeSessionId) {
    cliArgs.push("exec", "resume", opts.resumeSessionId, "--json", "--skip-git-repo-check");
  } else if (opts.continueSession) {
    cliArgs.push("exec", "resume", "--last", "--json", "--skip-git-repo-check");
  } else {
    cliArgs.push("exec", "--json", "--skip-git-repo-check");
  }

  if (opts.mode === "ask" || opts.mode === "plan") {
    cliArgs.push("--sandbox", "read-only");
  } else if (opts.mode === "agent") {
    cliArgs.push("--full-auto");
  }

  if (opts.model) {
    cliArgs.push("--model", opts.model);
  }

  if (!opts.resumeSessionId && !opts.continueSession) {
    cliArgs.push(opts.prompt);
  }

  const envVars = opts.extraEnv ?? detectCodexEnv() ?? {};

  return { cmd: opts.cliPath, args: cliArgs, extraEnv: envVars };
}
