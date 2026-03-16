# AI 任务下发示例

> 用途：`CLAUDE.md` 已承载仓库级长期规则；本文件只保留给人类下任务时可直接改写的最小示例，不再重复维护三套大段提示词。

## 1. 先确认文档路径

- 先定位文档仓库根目录，也就是 `CLAUDE.md` 所在目录，记为 `DOCS_ROOT`
- 如果当前就在本仓库内，通常可直接使用 `docs/...` 和 `playbooks/...`
- 如果本仓库作为 submodule 挂在代码仓库里，例如目录名叫 `MediAskDocs`，则应使用 `MediAskDocs/docs/...` 和 `MediAskDocs/playbooks/...`
- 如果父仓库自己也有 `docs/` 目录，优先使用 `DOCS_ROOT` 下的路径，不要混读
- 本文中的 `DOCS_ROOT/...` 只是占位写法；真正发给 AI 时，要替换成解析后的实际路径
- 如果父代码仓库还没有自己的根目录 `CLAUDE.md`，可先参考 `DOCS_ROOT/playbooks/CODE-REPO-CLAUDE-TEMPLATE.md`

## 2. 下任务时只补充什么

- 不要再把长期规则整段重写；默认以 `CLAUDE.md` 为准
- 只补充这次的实现范围、涉及接口/页面、验证要求和预期输出
- 后端一次一个任务包；前端一次 1~3 个连续页面；全栈一次一个连续小闭环
- 如果发现契约疑似过期，先指出问题，再决定是否修改权威文档

## 3. 最小示例

### 后端

```text
请先按 `DOCS_ROOT/CLAUDE.md` 的规则执行，并阅读其中要求的后端文档。

本次只做一个后端任务包：
- 任务：<例如 Task D：AI 问诊主链路>
- 接口：<填写接口>
- 表 / DTO：<填写涉及表或 DTO>

完成后请：
1. 运行最小验证或测试
2. 按实际完成情况更新 `DOCS_ROOT/playbooks/00B-P0-DEVELOPMENT-CHECKLIST.md` 和 `DOCS_ROOT/playbooks/00C-P0-BACKEND-TASKS.md`
3. 按 `DOCS_ROOT/playbooks/AI-CODE-REVIEW-CHECKLIST.md` 自检
4. 输出：实现内容、修改文件、验证结果、更新的清单项、最相邻未完成项
```

### 前端

```text
请先按 `DOCS_ROOT/CLAUDE.md` 的规则执行，并阅读其中要求的前端文档。

本次只做这些连续页面：
- 页面 / 路由：<填写页面和路由>
- 依赖接口：<填写接口>

完成后请：
1. 做最小联调或 mock 验证
2. 按实际完成情况更新 `DOCS_ROOT/playbooks/00B-P0-DEVELOPMENT-CHECKLIST.md` 和 `DOCS_ROOT/playbooks/00D-P0-FRONTEND-TASKS.md`
3. 按 `DOCS_ROOT/playbooks/AI-CODE-REVIEW-CHECKLIST.md` 自检
4. 输出：实现页面、修改文件、验证结果、更新的清单项、下一自然页面
```

### 全栈小闭环

```text
请先按 `DOCS_ROOT/CLAUDE.md` 的规则执行，并阅读其中要求的前后端文档。

本次只做一个连续小闭环：
- 闭环：<例如 导诊结果页 + registration-handoff 接口>

完成后请：
1. 先保证接口契约稳定，再完成页面承接
2. 做最小联调，并说明未联调部分
3. 按实际完成情况更新 `DOCS_ROOT/playbooks/00B-P0-DEVELOPMENT-CHECKLIST.md`、`DOCS_ROOT/playbooks/00C-P0-BACKEND-TASKS.md`、`DOCS_ROOT/playbooks/00D-P0-FRONTEND-TASKS.md`
4. 按 `DOCS_ROOT/playbooks/AI-CODE-REVIEW-CHECKLIST.md` 自检
5. 输出：本次闭环、前后端改动文件、验证结果、更新的清单项、下一自然闭环
```

## 4. 一句话结论

以后给 AI 下任务时，先指向 `CLAUDE.md`，再只写“这次具体做什么”；仓库级规则不要再在 prompt 里重复维护。
