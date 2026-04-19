---
article_id: OBA-mcp2cliguide01
tags: [open-source, mcp2cli, mcp, cli, guide]
type: tutorial
updated_at: 2026-04-19
---

# mcp2cli 仓库级导读指南

> 一行命令把任意 MCP Server / OpenAPI Spec / GraphQL Schema 变成可交互的 CLI —— 无需代码生成，全在运行时完成。

## 📌 项目概览

| 维度 | 说明 |
|------|------|
| **核心价值** | 将 MCP、OpenAPI、GraphQL 三种协议的 API 在运行时自动转换为 CLI 子命令，零代码生成 |
| **技术特征** | 纯 Python 单文件架构（`__init__.py` 3678 行），基于 argparse 动态构建，支持 stdio/SSE/Streamable HTTP 三种传输层 |
| **代码规模** | 核心源码 1 个文件（3678 行）+ 10 个测试文件，依赖仅 httpx / mcp / pyyaml |
| **版本** | v2.6.0，MIT 协议，要求 Python >= 3.10 |
| **作者** | Stephan Fitzpatrick ([knowsuchagency](https://github.com/knowsuchagency)) |

一句话概括：`mcp2cli` 通过统一的 `CommandDef` 数据模型，在运行时动态发现 API 工具并用 argparse 构建命令行，实现了"连接即 CLI"的体验。

## 🏗️ 系统架构

```
┌─────────────────────────────────────────────────────┐
│                    CLI 入口                          │
│              main() / _main_impl()                   │
└──────────┬──────────┬──────────┬────────────────────┘
           │          │          │
     ┌─────▼──┐  ┌────▼───┐  ┌──▼────────┐
     │  MCP   │  │ OpenAPI │  │  GraphQL  │
     │ Mode   │  │  Mode   │  │   Mode    │
     └────┬───┘  └───┬────┘  └────┬──────┘
          │          │            │
     ┌────▼──────────▼────────────▼────┐
     │   统一数据模型 CommandDef        │
     │   + ParamDef (参数定义)          │
     │   + 缓存层 (SHA256 key)         │
     └────────────┬───────────────────┘
                  │
         ┌────────▼────────┐
         │ build_argparse() │
         │ 动态构建 CLI     │
         └────────┬────────┘
                  │
     ┌────────────▼────────────────┐
     │     传输层 (Transport)       │
     │  stdio │ SSE │ Streamable   │
     └─────────────────────────────┘
```

**核心数据流**：用户输入 → 参数预解析 → 协议识别 → 连接/发现工具(或读缓存) → 动态构建 argparse → 匹配子命令 → 调用对应协议 API → 输出结果。

**技术栈**：

| 层级 | 技术选型 |
|------|---------|
| 语言 | Python 3.10+ |
| CLI 框架 | argparse（标准库，运行时动态构建） |
| HTTP 客户端 | httpx |
| MCP SDK | mcp >= 1.0 |
| 异步运行时 | anyio |
| 包管理 | uv |
| 测试 | pytest + pytest-asyncio |

## 🗺️ 关键文件地图

按阅读优先级排序：

| 优先级 | 文件 | 说明 | 风险等级 |
|--------|------|------|---------|
| P0 | `src/mcp2cli/__init__.py` | **全部核心逻辑**，3678 行单文件 | 高 — 任何修改都影响全局 |
| P1 | `pyproject.toml` | 项目配置、依赖、入口点定义 | 中 — 依赖变更需谨慎 |
| P2 | `tests/test_mcp.py` | MCP 集成测试 | 低 |
| P2 | `tests/test_openapi.py` | OpenAPI 集成测试 | 低 |
| P2 | `tests/test_graphql.py` | GraphQL 集成测试 | 低 |
| P3 | `tests/test_cache.py` | 缓存逻辑测试 | 低 |
| P3 | `tests/conftest.py` | 测试 fixtures | 低 |
| 参考 | `skills/mcp2cli/SKILL.md` | 项目自带的 Claude Code Skill 定义 | 参考 |

**高风险区域**（`__init__.py` 内）：

| 行号范围 | 功能 | 风险说明 |
|----------|------|---------|
| 48-75 | `ParamDef` / `CommandDef` 数据模型 | 三个协议共用，改一处影响全部 |
| 163-175 | JSON Schema → Python 类型映射 | 类型判断错误导致 CLI 参数解析失败 |
| 1751-1801 | `build_argparse()` | 核心 CLI 构建逻辑 |
| 2086-2090 | 传输层自动选择 | 回退逻辑影响所有远程 MCP 连接 |
| 3579-3678 | `_main_impl()` 主入口 | 参数预解析与模式分发 |

## 💡 核心设计决策

| 问题 | 方案 | 原因 |
|------|------|------|
| 三种协议如何统一？ | `CommandDef` + `ParamDef` 数据模型 | 一套 CLI 构建逻辑适配 MCP/OpenAPI/GraphQL，通过可选字段（`tool_name`/`method`/`graphql_field_name`）区分协议 |
| 如何避免每次启动都重新发现工具？ | 基于配置 SHA256 哈希的文件缓存 | MCP server 连接耗时较长，缓存 TTL 默认 1 小时，配置变化自动失效 |
| 如何处理 MCP 传输层差异？ | 自动探测：优先 Streamable HTTP，失败回退 SSE | 兼容新旧 MCP 协议，用户无需关心底层传输 |
| 为什么用单文件架构？ | 全部逻辑在 `__init__.py` | 对于 ~3600 行的工具类项目，单文件降低模块间协调复杂度，方便 `pipx run` 直接使用 |
| CLI 参数冲突怎么办？ | `_split_at_subcommand()` 将 argv 拆分 | 全局选项（如 `--env`）可能与工具参数同名，拆分后分别解析避免冲突（见 GH #15） |

## 🚀 本地搭建

```bash
# 1. 克隆源码（如已有可跳过）
git clone https://github.com/knowsuchagency/mcp2cli.git
cd mcp2cli

# 2. 安装 uv（Python 包管理器）
curl -LsSf https://astral.sh/uv/install.sh | sh

# 3. 安装依赖
uv sync

# 4. 运行（以远程 MCP server 为例）
uv run mcp2cli --mcp https://your-mcp-server.com

# 5. 运行测试
uv run pytest
```

快速体验（无需克隆）：
```bash
# 直接用 pipx 运行
pipx run mcp2cli --openapi https://petstore.swagger.io/v2/swagger.json
```

## 🐛 调试指南

**调试入口**：

| 场景 | 方法 |
|------|------|
| MCP 连接失败 | 设置 `--transport sse` 或 `--transport streamable` 强制指定传输层 |
| 缓存问题 | 使用 `--refresh` 强制刷新，或设置 `MCP2CLI_CACHE_DIR` 自定义缓存目录 |
| 参数解析异常 | 使用 `--verbose` 查看详细日志 |
| 查看可用命令 | 使用 `--list` 列出所有子命令，`--search <pattern>` 过滤 |

**常见问题**：

| 问题 | 原因 | 解决 |
|------|------|------|
| 连接远程 MCP 超时 | Streamable HTTP 失败后回退 SSE 有延迟 | 显式指定 `--transport sse` |
| 子命令参数被全局选项吞掉 | argparse 参数名冲突 | 已通过 `_split_at_subcommand()` 修复（v2.6.0+） |
| 工具列表为空 | MCP server 未返回工具或缓存过期 | `--refresh` 清除缓存重试 |
| `--help` 输出格式异常 | argparse 的 `%` 转义问题 | 项目用 `ARGPARSE_HELP_PERCENT_RE` 正则处理 |

## 🎯 适合谁用

| 角色 | 使用场景 |
|------|---------|
| **MCP Server 开发者** | 快速测试自建 MCP Server 的工具是否正常工作 |
| **CLI 爱好者** | 将任意 API 变成命令行工具，集成到脚本/自动化流程中 |
| **AI 工具开发者** | 理解 MCP 协议的客户端实现模式，参考动态 CLI 构建方案 |
| **DevOps 工程师** | 在 CI/CD 中通过 CLI 调用 MCP/OpenAPI 服务 |

## 📖 进阶阅读

- **已有笔记**：[MCP 协议集成机制](./mcp-integration/mcp-protocol-integration.md) — 详细分析了连接、发现、转换、执行四个阶段
- **源码关键位置**：`src/mcp2cli/__init__.py` 内搜索 `CommandDef`、`build_argparse`、`_extract_tools` 三个核心概念
- **上游项目**：[MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk) — mcp2cli 依赖的 MCP 客户端库
- **官方仓库**：[knowsuchagency/mcp2cli](https://github.com/knowsuchagency/mcp2cli)
