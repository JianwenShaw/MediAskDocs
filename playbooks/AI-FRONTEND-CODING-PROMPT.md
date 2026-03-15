# AI 前端开发提示词模板

> 用途：让 AI 在实现前端页面时，严格按页面任务、页面流转和 AI 对外契约落地，不自己发明页面状态和跳转分支。

## 1. 使用规则

- 一次只让 AI 做 1~3 个连续页面
- 明确本次只实现哪些页面和路由
- 明确要求它按 `nextAction` 驱动流转
- 明确要求它在结束前按 `AI-CODE-REVIEW-CHECKLIST.md` 自检
- 完成后回写前端任务清单，不要只改代码不改进度

## 2. 可直接复制模板

```text
请先阅读并严格遵守以下文档，不要自行扩 scope：

1. docs/00A-P0-BASELINE.md
2. playbooks/00B-P0-DEVELOPMENT-CHECKLIST.md
3. playbooks/00D-P0-FRONTEND-TASKS.md
4. playbooks/00F-P0-FRONTEND-PROTOTYPES-AND-FLOWS.md
5. docs/10A-JAVA_AI_API_CONTRACT.md
6. docs/08-FRONTEND.md

本次只实现以下页面：
- <填写页面名称>
- <填写路由>
- <填写依赖接口>

必须遵守：
- 页面跳转只根据结构化字段决定，尤其是 nextAction
- 不从聊天文案中猜推荐科室
- 高风险页和普通导诊结果页必须分开
- 页面成功/失败判断以 code 为准
- 页面报错时要保留 requestId

完成标准：
- 页面实现完成
- 路由可访问
- 能和对应接口联调或完成 mock 联调
- 已按 `playbooks/AI-CODE-REVIEW-CHECKLIST.md` 完成自检
- 完成后同步更新进度文档中的勾选状态

完成后请输出：
1. 本次实现了哪些页面
2. 修改了哪些文件
3. 做了哪些联调或 mock 验证
4. 把哪些清单项从 [ ] 改成了 [x]
5. 下一个最自然应该继续做的页面是什么

进度回写要求：
- 更新 playbooks/00B-P0-DEVELOPMENT-CHECKLIST.md
- 更新 playbooks/00D-P0-FRONTEND-TASKS.md
- 参考 playbooks/00F-P0-FRONTEND-PROTOTYPES-AND-FLOWS.md 的页面块和状态流转
- 除非接口契约本身有误，否则不要修改 docs/10A-JAVA_AI_API_CONTRACT.md
```

## 3. 推荐页面粒度

- 第一组：登录页 + AI 问诊页
- 第二组：导诊结果页 + 高风险提示页
- 第三组：挂号提交页 + 我的挂号页
- 第四组：工作台 + 接诊列表/详情页
- 第五组：病历编辑页 + 处方编辑页
- 第六组：审计查询页

## 4. 一句话结论

前端提示词最重要的是把“本次只做哪些页面、页面之间怎么跳、做完后去哪打勾”写清楚。
