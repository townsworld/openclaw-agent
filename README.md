# openclaw-agent

[OpenClaw](https://openclaw.ai) 插件 —— 在飞书中远程调用本机 AI 编程助手，对项目代码进行分析、调试和修改。

支持三大 CLI 引擎：**Cursor Agent** · **Claude Code** · **OpenAI Codex**，按需选装。

---

## 快速开始

### 前置条件

- [OpenClaw](https://openclaw.ai) 已安装并绑定飞书
- Node.js 18+（安装 Claude Code / Codex CLI 需要）
- macOS 或 Linux

### 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/townsworld/openclaw-agent/main/scripts/install.sh | bash
```

安装脚本会交互式引导完成以下步骤：

| 步骤 | 内容 |
|------|------|
| 1. 环境检查 | 确认 OpenClaw Gateway 已就绪 |
| 2. CLI 工具 | 交互式菜单，选装 Cursor / Claude Code / Codex（可多选） |
| 3. 认证配置 | 每个 CLI 安装后立即引导认证（标准登录优先，代理/API Key 可选） |
| 4. 模型选择 | 每个 CLI 认证后选择模型（使用默认或指定自定义模型） |
| 5. 下载插件 | 从 GitHub Release 获取最新版本 |
| 6. 写入配置 | 自动更新 `~/.openclaw/openclaw.json` |
| 7. 项目管理 | 扫描本机 git 仓库，勾选要管理的项目 |
| 8. 重启 Gateway | 自动重启以加载插件 |

**项目选择的默认行为**：
- 首次安装：默认全不选，用户主动勾选需要的项目
- 重新安装：只预选之前已配置的项目，新发现的默认不选

**远程/云端服务器**：Codex 登录会自动切换到 `--device-auth` 模式，无需浏览器回调。

### 更新插件

```bash
curl -fsSL https://raw.githubusercontent.com/townsworld/openclaw-agent/main/scripts/install.sh | bash -s -- --upgrade
```

`--upgrade` 模式只更新插件代码（`dist/index.js`、`SKILL.md` 等），跳过 CLI 安装、认证、模型选择和项目管理。版本相同时会提示是否重装。

也可以不加 `--upgrade` 重新运行安装命令，走完整流程。

### 一键卸载

```bash
curl -fsSL https://raw.githubusercontent.com/townsworld/openclaw-agent/main/scripts/uninstall.sh | bash
```

卸载插件文件和 `openclaw.json` 中的相关配置，不卸载 CLI 工具本身。

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

然后重启 Gateway：`openclaw gateway restart`

---

## 使用方式

### Slash 命令

在飞书中向 OpenClaw 发送：

```
/cursor my-backend 分析首页接口的性能瓶颈
/claude my-webapp 帮我 review 最近的改动
/codex my-backend 写一组单元测试覆盖用户注册逻辑
```

命令格式：`/<engine> <project> [options] <prompt>`

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

```
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

AI 会根据用户意图自动选择引擎和执行模式。如果指定的引擎不可用，会自动降级到其他可用引擎。

---

## 认证方式

安装时每个 CLI 的认证菜单**标准登录优先**，代理/API Key 其次。

### Cursor Agent

标准登录：`agent login`

### Claude Code

| 模式 | 说明 |
|------|------|
| 标准登录（推荐） | `claude login`，使用 Anthropic 账号 |
| 代理模式 | `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`，适用于企业内网代理 |

代理配置可写入 `openclaw.json`（适用于 LaunchAgent 等不加载 shell 环境变量的场景）：

```json
"claude": {
  "anthropicBaseUrl": "https://your-proxy.example.com",
  "anthropicAuthToken": "your-token"
}
```

### Codex

| 模式 | 说明 |
|------|------|
| 标准登录（推荐） | `codex login`，桌面环境走浏览器 OAuth，云端自动走 `--device-auth` |
| API Key 模式 | 设置 `OPENAI_API_KEY` 环境变量或在配置中指定 |

API Key 写入 `openclaw.json`：

```json
"codex": {
  "openaiApiKey": "sk-..."
}
```

---

## 配置参考

配置位于 `~/.openclaw/openclaw.json` → `plugins.entries.openclaw-agent.config`。所有配置项均有合理默认值。

### 全局

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `projects` | `{}` | 项目名 → 本机路径映射 |
| `defaultEngine` | `cursor` | `code_agent` 工具的默认引擎 |
| `defaultTimeoutSec` | `600` | 单次执行超时（秒）|
| `noOutputTimeoutSec` | `120` | 无输出超时（秒）|
| `maxConcurrent` | `3` | 最大并发进程数 |
| `enableAgentTool` | `true` | 是否注册自然语言自动调用工具 |

### Cursor

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `cursor.agentPath` | 自动检测 | CLI 路径 |
| `cursor.model` | CLI 默认 | 模型覆盖（安装时可交互选择） |
| `cursor.enableMcp` | `true` | 是否启用 MCP |

### Claude Code

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `claude.claudePath` | 自动检测 | CLI 路径 |
| `claude.model` | CLI 默认 | 模型覆盖（安装时可交互选择） |
| `claude.anthropicBaseUrl` | — | 代理 URL |
| `claude.anthropicAuthToken` | — | 代理认证令牌 |

### Codex

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `codex.codexPath` | 自动检测 | CLI 路径 |
| `codex.model` | CLI 默认 | 模型覆盖（安装时可交互选择） |
| `codex.openaiApiKey` | — | OpenAI API Key |

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
