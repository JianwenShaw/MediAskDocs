# AI 后端开发提示词模板

> 用途：让 AI 在实现后端代码时，先读基线文档，再只做一个明确任务包，并且在完成后回写进度清单。

## 1. 使用规则

- 一次只让 AI 做一个后端任务包
- 明确写出本次只实现哪些接口、表、DTO
- 明确要求它更新执行清单中的勾选状态
- 明确要求它在结束前按 `AI-CODE-REVIEW-CHECKLIST.md` 自检
- 除非发现文档契约错误，否则不要让它顺手改权威设计文档

## 2. 可直接复制模板

```text
请先阅读并严格遵守以下文档，不要自行扩 scope：

1. docs/00A-P0-BASELINE.md
2. playbooks/00B-P0-DEVELOPMENT-CHECKLIST.md
3. playbooks/00C-P0-BACKEND-TASKS.md
4. playbooks/00E-P0-BACKEND-ORDER-AND-DTOS.md
5. docs/10A-JAVA_AI_API_CONTRACT.md
6. docs/19-ERROR_EXCEPTION_RESPONSE_DESIGN.md

本次只实现以下内容：
- <填写本次任务包>
- <填写接口>
- <填写涉及表>

必须遵守：
- 浏览器只访问 Java，不直连 Python
- Java 对外 JSON 响应统一使用 Result<T>
- SSE 不要逐帧包 Result<T>
- request_id 是唯一主串联键
- Python 只写 knowledge_chunk_index 和 ai_run_citation

完成标准：
- 代码实现完成
- 本地运行最小验证或测试
- 不违反现有文档契约
- 已按 `playbooks/AI-CODE-REVIEW-CHECKLIST.md` 完成自检
- 完成后同步更新进度文档中的勾选状态

完成后请输出：
1. 本次实现了哪些条目
2. 修改了哪些文件
3. 运行了哪些验证
4. 把哪些清单项从 [ ] 改成了 [x]
5. 哪些相邻条目还未完成

进度回写要求：
- 更新 playbooks/00B-P0-DEVELOPMENT-CHECKLIST.md
- 更新 playbooks/00C-P0-BACKEND-TASKS.md
- 如果涉及接口字段或实现顺序确认，再同步参考 playbooks/00E-P0-BACKEND-ORDER-AND-DTOS.md
- 除非契约本身有误，否则不要修改 docs/10A-JAVA_AI_API_CONTRACT.md 和 docs/19-ERROR_EXCEPTION_RESPONSE_DESIGN.md
```

## 3. 推荐任务粒度

- Task A：公共协议与 request_id
- Task B：认证、角色、数据范围基线
- Task C：知识库与 RAG 底座
- Task D：AI 问诊主链路
- Task E：AI 到挂号承接
- Task F：医生接诊、病历、处方
- Task G：审计与敏感访问留痕

## 4. 一句话结论

后端提示词最重要的不是“多给上下文”，而是把阅读范围、实现边界、完成标准和进度回写位置一次说死。
