---
article_id: OBA-ojqdp76u
tags: [open-source, mcp2cli, RESEARCH-LOG.md, python, mcp, cli]
type: note
updated_at: 2026-04-03
---

# 研究日志

## 2026-04-03: MCP 协议集成机制

**研究主题**: MCP 协议集成机制

**研究问题**: mcp2cli 如何实现 MCP 协议集成？如何将 MCP server 转换为 CLI？

**仓库**: [mcp2cli](https://github.com/knowsuchagency/mcp2cli)

**核心发现**:
- mcp2cli 支持 stdio/SSE/Streamable HTTP 三种 MCP 传输层，自动回退选择
- 通过 `session.list_tools()` 发现 MCP 工具，获取 JSON Schema 格式的 inputSchema
- 将 JSON Schema 类型映射为 Python argparse 类型，动态构建 CLI
- 使用配置哈希缓存避免重复工具发现
- 统一的 CommandDef/ParamDef 数据模型适配 MCP/OpenAPI/GraphQL 三种协议

**进度（持续更新）**:
- questions: 1
- notes: 1
- guides: 0
- skill templates: 0
- runnable skills: 0

---
