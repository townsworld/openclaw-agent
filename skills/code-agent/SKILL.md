---
name: code-agent
description: |
  调用本机的 Cursor Agent、Claude Code 或 Codex CLI 来读取、分析、调试、修改项目代码。
  当用户提到项目名或要求使用 cursor/claude/codex 时，必须使用此工具。
---

# 代码分析工具 (code_agent)

## 🚨 执行前必读

- ✅ **当用户明确说"用 cursor"、"用 claude"、"用 codex"时**，必须调用此工具并设置对应的 engine 参数
- ✅ **当用户要求对项目进行深度分析、修改代码、调试 bug 等复杂任务时**，优先使用此工具
- ✅ **对于代码相关的输出**，保持 CLI 返回的代码片段、diff、错误日志等技术内容的完整性，不要截断或改写；但可以在前后添加简要说明帮助用户理解
- ✅ **如果用户的问题你可以直接回答**（如通用编程知识、不涉及具体项目代码），不需要调用此工具
- ✅ **CLI 报错时立即中断**，将错误信息告知用户，不要自己绕过处理
- ✅ **引擎不可用时自动降级**：如果返回 "Engine xxx is not available"，使用可用引擎重试，并告知用户实际使用的引擎

---

## 📋 快速索引：意图 → 参数

| 用户意图 | engine | mode | 说明 |
|---------|--------|------|------|
| "用 cursor 看看 xxx 项目" | cursor | ask | 只读分析 |
| "用 claude 帮我改代码" | claude | agent | 可修改文件 |
| "用 codex 写个测试" | codex | agent | 可修改文件 |
| "帮我看看 xxx 项目的架构" | (默认) | ask | 用户没指定引擎时用默认值 |
| "分析一下 xxx 的性能问题" | (默认) | ask | 只读分析 |
| "到 xxx 项目里修一下这个 bug" | (默认) | agent | 需要修改文件 |
| "帮我规划一下 xxx 的重构方案" | (默认) | plan | 生成方案不执行 |
| "继续上一个任务" | (默认) | (同上次) | 使用 --continue |

---

## 🎯 参数说明

### engine（引擎选择）

| 用户说法 | engine 值 |
|---------|-----------|
| "用 cursor" / "cursor 帮我" | `cursor` |
| "用 claude" / "claude 帮我" | `claude` |
| "用 codex" / "codex 帮我" | `codex` |
| 没有指定 | 不传，使用默认引擎 |

### mode（执行模式）

| mode | 含义 | 适用场景 |
|------|------|---------|
| `ask` | 只读分析，不修改任何文件 | 查看结构、分析问题、review 代码 |
| `plan` | 生成方案，不执行修改 | 重构规划、架构设计 |
| `agent` | 可以读写文件 | 修 bug、写代码、重构 |

**默认 mode 选择规则**：
- 用户说"看看"、"分析"、"review"、"查一下"、"什么原因" → `ask`
- 用户说"改"、"修"、"写"、"重构"、"添加"、"删除" → `agent`
- 用户说"规划"、"方案"、"设计" → `plan`
- **无法判断时，默认使用 `ask`**（只读分析，更安全）

### project（项目名）

从用户消息中提取项目名，必须是已配置的项目名之一。

### prompt（任务描述）

将用户的具体需求转化为清晰的任务描述，传递给 CLI 引擎。

---

## ⚙️ 引擎差异须知

三个引擎在功能上基本等价，以下是需要关注的差异：

| 特性 | Cursor | Claude Code | Codex |
|------|--------|-------------|-------|
| ask / plan / agent 模式 | ✅ 均支持 | ✅ 均支持 | ✅ 均支持（plan 效果同 ask） |
| 继续会话 | ✅ | ✅ | ✅ |
| 恢复指定会话 | ✅ | ✅ | ✅ |
| 指定模型 | ✅ | ✅ | ✅ |

**注意**：Codex 的 `plan` 模式底层与 `ask` 相同（都是只读沙箱），不会生成与 Cursor/Claude 不同的规划输出。

---

## 📌 使用场景示例

### 场景 1: 用 cursor 查看项目结构

用户说：`用 cursor 看看 my-backend 项目的结构`

```json
{
  "engine": "cursor",
  "project": "my-backend",
  "prompt": "分析这个项目的整体架构和目录结构，列出核心模块及其功能",
  "mode": "ask"
}
```

### 场景 2: 用 claude 分析 bug

用户说：`用 claude 帮我看看 my-webapp 里登录页面的崩溃问题`

```json
{
  "engine": "claude",
  "project": "my-webapp",
  "prompt": "分析登录页面的崩溃问题，查看相关的错误处理和异常逻辑",
  "mode": "ask"
}
```

### 场景 3: 用 codex 修改代码

用户说：`用 codex 到 my-backend 里加一个健康检查接口`

```json
{
  "engine": "codex",
  "project": "my-backend",
  "prompt": "添加一个 /health 健康检查接口，返回服务状态",
  "mode": "agent"
}
```

### 场景 4: 未指定引擎，默认分析

用户说：`帮我看看 my-backend 的数据库连接池配置`

```json
{
  "project": "my-backend",
  "prompt": "检查数据库连接池的配置，分析是否有性能或泄漏风险",
  "mode": "ask"
}
```

### 场景 5: 规划重构方案

用户说：`帮我规划一下 my-webapp 的状态管理重构`

```json
{
  "project": "my-webapp",
  "prompt": "分析当前的状态管理方案，规划一个迁移到 Pinia 的重构方案",
  "mode": "plan"
}
```

### 场景 6: 继续上一个任务

用户说：`继续上一个 my-backend 的任务`

```json
{
  "project": "my-backend",
  "prompt": "继续上一个任务",
  "mode": "agent"
}
```
（工具内部会自动使用 --continue）

---

## 🔍 常见问题

| 问题 | 原因 | 解决 |
|------|------|------|
| 工具返回 "Project not found" | 项目名拼写错误或未配置 | 检查 openclaw.json 中的项目配置 |
| 执行超时 | 任务太复杂或 CLI 卡住 | 缩小 prompt 范围，拆分任务 |
| 返回空结果 | CLI 未正确认证 | 检查 cursor/claude/codex 的登录状态 |
| Engine 不可用 | 对应的 CLI 未安装 | 自动使用可用引擎重试，并告知用户 |
| Codex 报认证失败 | API Key 未配置 | 运行 `codex login` 或设置 OPENAI_API_KEY 环境变量 |

---

## 🔧 引擎选择建议

| 场景 | 推荐引擎 | 原因 |
|------|---------|------|
| 快速代码分析 | cursor | 启动最快，对项目上下文理解好 |
| 深度 code review | claude | 分析能力强，善于发现潜在问题 |
| 批量代码修改 | codex | 执行效率高，适合自动化任务 |
| 架构设计规划 | claude | 长文本推理能力强 |
| 用户没有偏好 | 使用默认引擎 | 由配置决定 |
