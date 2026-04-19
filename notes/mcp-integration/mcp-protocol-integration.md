---
article_id: OBA-30xu2kkz
tags: [open-source, mcp2cli, mcp-integration, python, mcp, cli]
type: learning
updated_at: 2026-04-03
---

# mcp2cli 的 MCP 协议集成机制

> mcp2cli 如何在运行时将 MCP server 的工具动态转换为 CLI 命令，无需任何代码生成

## 背景问题

mcp2cli 是如何将一个 MCP server 的工具（tools）动态发现并映射为 CLI 子命令的？整个流程涉及连接、发现、转换、执行四个阶段。

## 核心发现

### 一、MCP 连接方式

mcp2cli 支持三种 MCP 传输层：

| 方式 | 适用场景 | 连接方式 |
|------|---------|---------|
| **stdio** | 本地 MCP server 进程 | 启动子进程，通过 stdin/stdout 通信 |
| **SSE** | 远程 MCP server（旧协议） | HTTP + Server-Sent Events |
| **Streamable HTTP** | 远程 MCP server（新协议） | 原生 HTTP 流式传输 |

自动选择逻辑：优先尝试 Streamable HTTP，失败后回退到 SSE。

**关键代码**：`src/mcp2cli/__init__.py:2086-2090`

```python
if transport == "sse":
    return await _via_sse()
elif transport == "streamable":
    return await _via_streamable()
else:  # auto
    try:
        return await _via_streamable()
    except Exception:
        return await _via_sse()
```

### 二、工具发现机制

连接 MCP server 后，通过 `session.list_tools()` 获取所有可用工具：

```python
# src/mcp2cli/__init__.py:2934-3006
async def _extract_tools(session):
    result = await session.list_tools()
    tools_result.extend(
        {
            "name": t.name,
            "description": t.description or "",
            "inputSchema": t.inputSchema or {},
        }
        for t in result.tools
    )
```

每个 MCP tool 的 `inputSchema` 遵循 JSON Schema 规范，包含参数名、类型、是否必填等信息。

### 三、参数映射原理

mcp2cli 将 JSON Schema 类型映射为 Python argparse 类型：

| JSON Schema 类型 | Python 类型 | CLI 行为 |
|------------------|------------|---------|
| `integer` | `int` | `--arg 42` |
| `number` | `float` | `--arg 3.14` |
| `boolean` | `None`（store_true） | `--flag` |
| `array` | `str`（JSON 字符串） | `--arg '[1,2]'` |
| `object` | `str`（JSON 字符串） | `--arg '{"k":"v"}'` |
| `string` | `str` | `--arg hello` |

**关键代码**：`src/mcp2cli/__init__.py:163-175`

### 四、命令名称转换

MCP tool 名自动转为 kebab-case CLI 子命令名：

```python
# src/mcp2cli/__init__.py:222-224
def to_kebab(name: str) -> str:
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", name)
    return s.replace("_", "-").lower()
```

示例：`echoMessage` → `echo-message`，`list_items` → `list-items`

### 五、CLI 动态构建

使用 Python 标准库 `argparse` 动态构建命令行解析器：

```python
# src/mcp2cli/__init__.py:1751-1801
def build_argparse(commands: list[CommandDef], ...):
    parser = argparse.ArgumentParser(prog="mcp2cli")
    subparsers = parser.add_subparsers(dest="_command")

    for cmd in commands:
        sub = subparsers.add_parser(cmd.name, help=cmd.description)
        sub.set_defaults(_cmd=cmd)

        for p in cmd.params:
            flag = f"--{p.name}"
            if p.python_type is not None:
                kwargs["type"] = p.python_type
            else:
                kwargs["action"] = "store_true"
```

### 六、缓存机制

为避免每次都重新发现工具，使用基于配置哈希的文件缓存：

```python
# src/mcp2cli/__init__.py:355-382
def cache_key_for(config: dict) -> str:
    # 过滤不影响结果的字段，对剩余配置做 SHA256 哈希
    return hashlib.sha256(
        json.dumps(cache_config, sort_keys=True).encode()
    ).hexdigest()[:16]

def load_cached(key: str, ttl: int) -> dict | None:
    path = CACHE_DIR / f"{key}.json"
    if age >= ttl:
        return None  # 缓存过期
    return json.loads(path.read_text())
```

### 七、执行流程

完整调用链：

```
用户执行 CLI 命令
  → argparse 解析参数
  → 判断来源（MCP/OpenAPI/GraphQL）
  → 建立连接（stdio/HTTP/SSE）
  → session.initialize() 初始化会话
  → session.list_tools() 发现工具（或读缓存）
  → 构建 CommandDef 列表
  → build_argparse() 动态生成 CLI
  → 匹配用户输入的子命令
  → 调用 session.call_tool(tool_name, arguments)
  → 输出结果
```

## 关键代码位置

| 文件 | 行号 | 说明 |
|------|------|------|
| `src/mcp2cli/__init__.py` | 163-175 | JSON Schema → Python 类型映射 |
| `src/mcp2cli/__init__.py` | 222-224 | 命令名 kebab-case 转换 |
| `src/mcp2cli/__init__.py` | 355-382 | 缓存键生成与文件缓存 |
| `src/mcp2cli/__init__.py` | 1751-1801 | argparse 动态构建 |
| `src/mcp2cli/__init__.py` | 1996-2092 | HTTP/SSE 连接实现 |
| `src/mcp2cli/__init__.py` | 2086-2090 | 传输层自动选择 |
| `src/mcp2cli/__init__.py` | 2095-2156 | stdio 连接实现 |
| `src/mcp2cli/__init__.py` | 2934-3006 | MCP 工具发现 |
| `src/mcp2cli/__init__.py` | 3579-3674 | 主程序入口 |

## 设计亮点

1. **统一数据模型**：`CommandDef` + `ParamDef` 统一了 MCP、OpenAPI、GraphQL 三种协议的命令描述
2. **传输层抽象**：stdio/SSE/Streamable HTTP 三种方式通过统一的 `ClientSession` 接口操作
3. **渐进回退**：自动尝试新协议，失败后回退到旧协议
4. **零代码生成**：完全依赖运行时动态构建，无需预编译或代码生成步骤

## 可复用模式

### 模式 1：运行时动态 CLI 构建

```python
# 核心思路：从 API 规范中提取命令定义，然后用 argparse 动态构建
commands = extract_commands_from_spec(spec)  # 统一提取
parser = build_argparse(commands)             # 动态构建
args = parser.parse_args()                    # 标准解析
```

### 模式 2：多协议适配器

```python
# 统一的 CommandDef 数据模型适配不同协议
@dataclass
class CommandDef:
    name: str
    params: list[ParamDef]
    # 协议特定字段
    tool_name: str | None = None       # MCP
    method: str | None = None          # OpenAPI
    graphql_field_name: str | None = None  # GraphQL
```

### 模式 3：配置哈希缓存

```python
# 基于配置内容生成缓存键，自动失效
key = hashlib.sha256(json.dumps(config, sort_keys=True).encode()).hexdigest()[:16]
```
