# Execution Playbooks

> 目录定位：`docs/` 保留权威设计与约束口径；`playbooks/` 只放实施清单、任务拆分、页面流转和 AI 协作提示词。

## 1. 为什么单独拆目录

把执行文档放到 `playbooks/` 的原因很简单：

- `docs/` 更适合放稳定的设计基线、架构约束和协议文档
- `playbooks/` 更适合放会跟着开发推进持续打勾、持续调整的执行材料
- AI 提示词也属于“协作流程资产”，不属于产品设计文档本身

## 2. 推荐阅读顺序

1. `../docs/00A-P0-BASELINE.md`
2. `00B-P0-DEVELOPMENT-CHECKLIST.md`
3. `00C-P0-BACKEND-TASKS.md`
4. `00D-P0-FRONTEND-TASKS.md`
5. `00E-P0-BACKEND-ORDER-AND-DTOS.md`
6. `00F-P0-FRONTEND-PROTOTYPES-AND-FLOWS.md`

## 3. AI 协作提示词

- `AI-BACKEND-CODING-PROMPT.md`
- `AI-FRONTEND-CODING-PROMPT.md`
- `AI-CODE-REVIEW-CHECKLIST.md`

## 4. 一句话结论

`docs/` 管“应该怎么做”，`playbooks/` 管“这次具体做什么、做到哪、怎么让 AI 按文档落地”。
