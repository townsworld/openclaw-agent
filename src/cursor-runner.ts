import { existsSync, readdirSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import type { ResolvedBinary, RunOptions } from "./types.js";

const VERSION_PATTERN = /^\d{4}\.\d{1,2}\.\d{1,2}-[a-f0-9]+$/;

function versionToNum(name: string): number {
  const datePart = name.split("-")[0]!;
  const [year, month, day] = datePart.split(".");
  return parseInt(`${year}${month!.padStart(2, "0")}${day!.padStart(2, "0")}`, 10);
}

function probeDir(dir: string): ResolvedBinary | null {
  const nodeBin = join(dir, "node");
  const entry = join(dir, "index.js");
  if (existsSync(nodeBin) && existsSync(entry)) {
    return { nodeBin, entryScript: entry };
  }
  return null;
}

function probeVersions(baseDir: string): ResolvedBinary | null {
  const versionsDir = join(baseDir, "versions");
  if (!existsSync(versionsDir)) return null;

  let entries: string[];
  try {
    entries = readdirSync(versionsDir);
  } catch {
    return null;
  }

  const matched = entries
    .filter((name) => VERSION_PATTERN.test(name))
    .sort((a, b) => versionToNum(b) - versionToNum(a));

  for (const ver of matched) {
    const result = probeDir(join(versionsDir, ver));
    if (result) return result;
  }
  return null;
}

export function resolveAgentBinary(agentPath: string): ResolvedBinary | null {
  const baseDir = dirname(resolve(agentPath));

  const direct = probeDir(baseDir);
  if (direct) return direct;

  const versioned = probeVersions(baseDir);
  if (versioned) return versioned;

  return null;
}

/** Build CLI args for Cursor Agent */
export function buildCursorArgs(opts: RunOptions): { cmd: string; args: string[] } {
  const resolved = opts.resolvedBinary;
  const cliArgs: string[] = [];

  if (resolved) {
    cliArgs.push(resolved.entryScript);
  }

  cliArgs.push(
    ...(opts.prefixArgs ?? []),
    "-p", "--trust",
    "--output-format", "stream-json",
  );

  if (opts.resumeSessionId) {
    cliArgs.push("--resume", opts.resumeSessionId);
  } else if (opts.continueSession) {
    cliArgs.push("--continue");
  } else if (opts.mode !== "agent") {
    cliArgs.push("--mode", opts.mode);
  }

  if (opts.enableMcp) {
    cliArgs.push("--approve-mcps", "--force");
  }
  if (opts.model) {
    cliArgs.push("--model", opts.model);
  }

  cliArgs.push(opts.prompt);

  const cmd = resolved ? resolved.nodeBin : opts.cliPath;
  return { cmd, args: cliArgs };
}
