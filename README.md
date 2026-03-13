# openclaw-agent

[OpenClaw](https://openclaw.dev) 插件 —— 从飞书远程调用本机的 AI 编程助手，对代码进行分析、排查和修改。

支持三大 CLI 引擎：**Cursor Agent** / **Claude Code** / **OpenAI Codex**，按需选装。

---

## 快速开始

### 前置条件

- [OpenClaw Gateway](https://openclaw.dev) 已安装并绑定飞书
- Node.js 18+

### 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/townsworld/openclaw-agent/main/scripts/install.sh | bash
```

安装脚本会引导你完成所有配置：

1. **检查 OpenClaw** — 确认 Gateway 已就绪
2. **CLI 工具菜单** — 交互式选装 Cursor / Claude Code / Codex（可选装一个或多个）
3. **认证引导** — 自动检测代理模式或引导登录
4. **下载插件** — 从 GitHub Release 获取最新版本
5. **配置写入** — 自动更新 `~/.openclaw/openclaw.json`
6. **项目发现** — 扫描本机 git 仓库，勾选要管理的项目

### 手动安装

```bash
gh release download -R townsworld/openclaw-agent -p "*.tgz"
mkdir -p ~/.openclaw/extensions/openclaw-agent
tar -xzf openclaw-agent-*.tgz -C ~/.openclaw/extensions/openclaw-agent --strip-components=1
```

然后在 `~/.openclaw/openclaw.json` 的 `plugins` 中添加：

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

---

## 使用方式

在飞书中向 OpenClaw 发送消息：

```
/cursor my-backend 分析首页接口的性能瓶颈
/claude my-webapp 帮我 review 最近的改动
/codex my-backend 写一组单元测试覆盖用户注册逻辑
```

### 命令格式

```
/<engine> <project> [options] <prompt>
```

| 部分 | 说明 |
|------|------|
| `<engine>` | `cursor` / `claude` / `codex` |
| `<project>` | 配置中的项目名，或本机绝对路径 |
| `<prompt>` | 你要 AI 做的事情 |

### 可选参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--mode ask\|plan\|agent` | `ask` 只读分析，`plan` 生成方案，`agent` 可修改文件 | `agent` |
| `--continue` | 继续上一次会话 | — |
| `--resume <id>` | 恢复指定会话 | — |

### 示例

```bash
# 只读分析，不修改代码
/cursor my-backend --mode ask 这个 NPE 崩溃是什么原因

# 让 AI 直接改代码
/claude my-webapp --mode agent 把登录页改成暗色主题

# 继续之前的对话
/codex my-backend --continue 上次的重构还需要处理哪些文件
```

### AI 自动调用

插件还注册了 `code_agent` 工具。在飞书中直接用自然语言提问即可，OpenClaw 的 AI 会自动判断是否需要调用代码分析：

```
帮我看看 my-backend 项目的架构
到 my-webapp 里检查有没有内存泄漏
```

---

## 认证

### Cursor Agent

```bash
agent login
```

### Claude Code

两种模式，插件启动时自动检测：

| 模式 | 条件 | 说明 |
|------|------|------|
| 代理模式 | 环境变量 `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN` 已设置 | 自动注入子进程，无需登录 |
| 标准模式 | 未检测到代理变量 | 使用 `claude login` 本地凭证 |

代理模式的凭证也可以写在插件配置中（适用于 LaunchAgent 等无 shell 环境的场景）：

```json
"claude": {
  "anthropicBaseUrl": "https://your-proxy.example.com",
  "anthropicAuthToken": "your-token"
}
```

### Codex

两种模式：

| 模式 | 条件 | 说明 |
|------|------|------|
| API Key | 环境变量 `CODEX_API_KEY` 或 `OPENAI_API_KEY` 已设置 | 直接使用 |
| 标准模式 | 未检测到 API Key | 使用 `codex login`（ChatGPT OAuth）|

---

## 配置参考

所有配置项均有合理默认值，通常无需手动调整。

### 全局

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `projects` | `{}` | 项目名 → 本机路径 |
| `defaultTimeoutSec` | `600` | 单次执行超时（秒）|
| `noOutputTimeoutSec` | `120` | 无输出超时（秒）|
| `maxConcurrent` | `3` | 最大并发进程数 |
| `defaultEngine` | `cursor` | `code_agent` 工具默认引擎 |
| `enableAgentTool` | `true` | 是否注册 AI 自动调用工具 |

### Cursor

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `cursor.agentPath` | 自动检测 | CLI 可执行文件路径 |
| `cursor.model` | CLI 默认 | 模型覆盖 |
| `cursor.enableMcp` | `true` | 是否启用 MCP 服务器 |

### Claude Code

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `claude.claudePath` | 自动检测 | CLI 可执行文件路径 |
| `claude.model` | CLI 默认 | 模型覆盖 |
| `claude.anthropicBaseUrl` | — | 代理 URL |
| `claude.anthropicAuthToken` | — | 代理认证令牌 |

### Codex

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `codex.codexPath` | 自动检测 | CLI 可执行文件路径 |
| `codex.model` | CLI 默认 | 模型覆盖 |
| `codex.openaiApiKey` | — | OpenAI API Key |

---

## 开发

```bash
npm install       # 安装依赖
npm run dev       # 监听文件变化
npm run build     # 构建
npm run pack      # 打包 .tgz
```

## License

Apache-2.0
