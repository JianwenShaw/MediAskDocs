# UV 使用指南

> Python 包管理器与虚拟环境工具

## 为什么用 uv？

- **速度快**：比 pip 快 10-100 倍
- **单工具**：替代 pip、pip-tools、venv、pyenv 部分功能
- **兼容性好**：完全兼容 PyPI 和现有 Python 工作流

---

## 安装

```bash
# macOS
brew install uv

# Linux / WSL
curl -LsSf https://astral.sh/uv/install.sh | sh

# pip 安装（任何 Python 环境）
pip install uv
```

---

## 与 pyenv 配合

uv 负责依赖管理，pyenv 负责 Python 版本管理：

```bash
# pyenv 安装并设置 Python 版本
pyenv install 3.11
pyenv local 3.11

# uv 自动检测并使用 pyenv 的 Python
uv run python --version  # 显示 3.11
```

---

## 常用命令速查

### 初始化项目

```bash
uv init              # 创建 pyproject.toml
uv init --python 3.11  # 指定 Python 版本
```

### 虚拟环境

```bash
uv venv                    # 创建 .venv 虚拟环境
uv venv --python 3.11     # 指定 Python 版本
source .venv/bin/activate  # 激活（手动）
```

### 安装依赖

```bash
uv add <包名>              # 添加生产依赖
uv add --dev <包名>        # 添加开发依赖
uv add 'fastapi>=0.109'   # 指定版本
uv add 'requests[security]'  # 添加可选依赖

uv pip install <包名>       # 兼容旧用法
uv pip install -r requirements.txt
```

### 运行命令

```bash
uv run python main.py      # 自动创建/使用虚拟环境并运行
uv run pytest             # 运行测试
uv run pytest -v           # 带参数
uv run --with httpx pytest # 临时添加依赖运行
uv run python --version    # 查看 Python 版本
```

### 管理依赖

```bash
uv pip list                # 列出已安装包
uv pip freeze              # 导出已安装包
uv pip freeze > requirements.txt
uv pip-sync requirements.txt  # 同步到 requirements.txt
uv remove <包名>           # 移除依赖
uv upgrade <包名>          # 升级依赖
uv tree                    # 显示依赖树
uv lock                     # 生成 lock 文件
uv sync                     # 根据 lock 文件安装依赖
```

### 导出

```bash
uv pip freeze > requirements.txt
uv export -o requirements.txt
```

---

## pyproject.toml 示例

```toml
[project]
name = "mediask-ai"
version = "0.1.0"
description = "MediAsk AI Service"
requires-python = ">=3.11.14"
dependencies = [
    "fastapi[standard]>=0.128.1",
    "langchain>=1.2.8",
    "langgraph>=1.0.7",
    "openai>=2.17.0",
    "pydantic-settings>=2.0.0",
    "pymilvus>=2.6.8",
]

[tool.uv]
dev-dependencies = [
    "pytest>=8.0.0",
    "pytest-asyncio>=0.23.0",
    "httpx>=0.26.0",
    "pytest-cov>=7.0.0",
    "ruff>=0.15.0",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

---

## AI 服务依赖推荐

```bash
# 核心依赖
uv add fastapi uvicorn langchain langgraph pymilvus openai

# 实用工具
uv add sse-starlette aiofiles python-dotenv

# 开发依赖
uv add --dev pytest pytest-asyncio httpx ruff black
```

---

## 对比 pip

| 操作 | pip | uv |
|-----|-----|-----|
| 安装包 | `pip install requests` | `uv add requests` |
| 批量安装 | `pip install -r requirements.txt` | `uv sync` |
| 运行脚本 | `python script.py` | `uv run python script.py` |
| 创建虚拟环境 | `python -m venv .venv` | `uv venv` |
| 导出依赖 | `pip freeze > requirements.txt` | `uv export` |

---

## 常见问题

### Q: uv 和 uvx 区别？

- `uv` - 包管理器
- `uvx` - 临时运行工具（类似 `npx`）

```bash
uvx black .           # 临时运行 black
uvx ruff check .      # 临时运行 ruff 检查
```