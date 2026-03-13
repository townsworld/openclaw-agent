# openclaw-agent

[OpenClaw](https://openclaw.ai) 插件 —— 在飞书中远程调用本机 AI 编程助手，对项目代码进行分析、调试和修改。

支持三大 CLI 引擎：**Cursor Agent** · **Claude Code** · **OpenAI Codex**，按需选装。

---

## 快速开始

### 前置条件

- [OpenClaw](https://openclaw.ai) 已安装并绑定飞书
- Node.js 18+（用于安装 Claude Code / Codex CLI）

### 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/townsworld/openclaw-agent/main/scripts/install.sh | bash
```

安装脚本会交互式引导完成以下步骤：

1. 检查 OpenClaw Gateway 是否就绪
2. 选装 CLI 工具（Cursor / Claude Code / Codex，可多选）
3. 认证配置 —— 每个 CLI 都可以选择标准登录或代理/API Key 模式
4. 下载插件包（从 GitHub Release 获取最新版本）
5. 写入配置到 `~/.openclaw/openclaw.json`
6. 自动扫描本机 git 仓库，选择要管理的项目

### 更新插件

```bash
curl -fsSL https://raw.githubusercontent.com/townsworld/openclaw-agent/main/scripts/install.sh | bash -s -- --upgrade
```

`--upgrade` 模式只更新插件代码和 SKILL，跳过 CLI 安装、认证配置和项目发现。如果本地已是最新版本，会提示并跳过。

也可以不加 `--upgrade` 直接重新运行安装命令，会走完整流程。

### 一键卸载

```bash
curl -fsSL https://raw.githubusercontent.com/townsworld/openclaw-agent/main/scripts/uninstall.sh | bash
```

### 手动安装

```bash
gh release download -R townsworld/openclaw-agent -p "*.tgz"
mkdir -p ~/.openclaw/extensions/openclaw-agent
tar -xzf openclaw-agent-*.tgz -C ~/.openclaw/extensions/openclaw-agent --strip-components=1
```

在 `~/.openclaw/openclaw.json` 的 `plugins` 中添加：

```json
{
  "allow": ["openclaw-agent"],
  "entries": {
    "openclaw-agent": {
      "enabled": true,
      "config": {
        "projects": {
          "my-backend": "/path/to/my-backend",
          "my-webapp": "/path/to/my-webapp"
        }
      }
    }
  }
}
```

然后重启 Gateway：

```bash
openclaw gateway restart
```

---

## 使用方式

### Slash 命令

在飞书中向 OpenClaw 发送：

```
/cursor my-backend 分析首页接口的性能瓶颈
/claude my-webapp 帮我 review 最近的改动
/codex my-backend 写一组单元测试覆盖用户注册逻辑
```

命令格式：

```
/<engine> <project> [options] <prompt>
```

| 部分 | 说明 |
|------|------|
| `<engine>` | `cursor` / `claude` / `codex` |
| `<project>` | 配置中的项目名 |
| `<prompt>` | 你希望 AI 执行的任务描述 |

可选参数：

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--mode ask\|plan\|agent` | `ask` 只读分析 · `plan` 生成方案 · `agent` 可修改文件 | `agent` |
| `--continue` | 继续上一次会话 | — |
| `--resume <id>` | 恢复指定会话 | — |

示例：

```bash
/cursor my-backend --mode ask 这个 NPE 崩溃是什么原因
/claude my-webapp --mode agent 把登录页改成暗色主题
/codex my-backend --continue 上次的重构还需要处理哪些文件
```

### 自然语言调用

插件注册了 `code_agent` 工具，直接用自然语言提问，OpenClaw AI 会自动判断是否需要调用代码分析：

```
帮我看看 my-backend 的架构
到 my-webapp 里检查有没有内存泄漏
用 claude 分析一下 my-backend 的数据库查询性能
```

---

## 认证方式

安装脚本中，每个 CLI 的认证菜单都会优先提供**标准登录**，其次是代理/API Key 模式。

### Cursor Agent

```bash
agent login
```

### Claude Code

| 模式 | 说明 |
|------|------|
| 标准登录 | `claude login`，使用 Anthropic 账号认证 |
| 代理模式 | 设置 `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN` 环境变量，或在插件配置中指定 |

代理配置也可写入 `openclaw.json`（适用于 LaunchAgent 等不加载 shell 环境变量的场景）：

```json
"claude": {
  "anthropicBaseUrl": "https://your-proxy.example.com",
  "anthropicAuthToken": "your-token"
}
```

### Codex

| 模式 | 说明 |
|------|------|
| 标准登录 | `codex login`，使用 OpenAI / ChatGPT 账号认证 |
| API Key 模式 | 设置 `OPENAI_API_KEY` 环境变量，或在插件配置中指定 |

API Key 配置写入 `openclaw.json`：

```json
"codex": {
  "openaiApiKey": "sk-..."
}
```

---

## 配置参考

所有配置项均有合理默认值，通常无需手动调整。配置位于 `~/.openclaw/openclaw.json` 的 `plugins.entries.openclaw-agent.config` 中。

### 全局

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `projects` | `{}` | 项目名 → 本机路径映射 |
| `defaultTimeoutSec` | `600` | 单次执行超时（秒）|
| `noOutputTimeoutSec` | `120` | 无输出超时（秒）|
| `maxConcurrent` | `3` | 最大并发进程数 |
| `defaultEngine` | `cursor` | `code_agent` 工具的默认引擎 |
| `enableAgentTool` | `true` | 是否注册自然语言自动调用工具 |

### Cursor

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `cursor.agentPath` | 自动检测 | CLI 可执行文件路径 |
| `cursor.model` | CLI 默认 | 模型覆盖 |
| `cursor.enableMcp` | `true` | 是否启用 MCP |

### Claude Code

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `claude.claudePath` | 自动检测 | CLI 可执行文件路径 |
| `claude.model` | CLI 默认 | 模型覆盖 |
| `claude.anthropicBaseUrl` | — | 代理 URL（可选）|
| `claude.anthropicAuthToken` | — | 代理认证令牌（可选）|

### Codex

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `codex.codexPath` | 自动检测 | CLI 可执行文件路径 |
| `codex.model` | CLI 默认 | 模型覆盖 |
| `codex.openaiApiKey` | — | OpenAI API Key（可选）|

---

## 开发

```bash
npm install       # 安装依赖
npm run dev       # 监听文件变化，自动构建
npm run build     # 单次构建
npm run pack      # 构建并打包 .tgz
npm test          # 运行测试
```

## License

Apache-2.0
