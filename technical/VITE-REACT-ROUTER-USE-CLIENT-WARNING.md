# Vite / React Router `use client` 构建警告说明

> 同步时间：2026-04-07
> 适用范围：`mediask-frontend` 当前 patient H5 前端

## 1. 现象

执行 `pnpm build:patient` 时，构建日志会出现类似提示：

```text
Module level directives cause errors when bundled, "use client" ... was ignored.
```

当前仓库中，这条提示来自 `react-router` 的发布包入口文件。

## 2. 原因

- `react-router` 在发布包入口中包含顶层 `"use client"` 指令。
- `"use client"` 是 React Server Components 语义的一部分，用于标记客户端组件边界。
- 当前项目是普通 Vite SPA 构建，不是 RSC 构建流程。
- 在当前 Vite 7 + Rollup 4 的打包链路里，这类模块级指令不会保留到 bundle 中，因此 Rollup 会打印 `MODULE_LEVEL_DIRECTIVE` 类告警，并说明该指令被忽略。

这不是业务代码错误，也不是本次 patient flow 修复引入的新问题。

## 3. 当前仓库结论

基于当前本地环境核对结果：

- Vite：`7.3.1`
- React Router：`7.13.2`
- Rollup：`4.60.1`
- `react-router/dist/development/index.mjs` 与 `dom-export.mjs` 入口文件都带有 `"use client"`
- `pnpm build:patient` 仍然成功，退出码为 `0`

结论：

- 对当前项目而言，这条日志属于信息性警告，不会阻塞打包。
- 如果项目继续保持普通 SPA 形态，可以接受这条警告存在。
- 如果只是想让构建日志更干净，应该在 Vite/Rollup 层精确过滤该告警，而不是改业务代码。

## 4. 是否需要修复

当前建议分两类看：

- 不需要立即修复：如果团队能接受这条日志，保持现状即可。
- 需要安静日志：在 `vite.config.ts` 中按 `warning.code === "MODULE_LEVEL_DIRECTIVE"` 且命中 `react-router` + `"use client"` 做定向过滤。

不建议为了这条日志单独调整业务实现。

也不建议仅为了消除这条日志就贸然升级依赖；那会引入额外验证成本，并且按仓库规则需要人工处理依赖变更。

## 5. 后续处理建议

- 默认策略：先不改代码，接受该警告。
- 若后续团队明确要求“构建日志无该提示”，再单独提交一次仅包含 Vite 告警过滤的配置变更。
- 若未来前端架构切换到 React Router 的 RSC 相关构建路径，再重新评估这条指令的处理方式。

## 6. 参考资料

- React `use client` 文档：<https://react.dev/reference/rsc/use-client>
- React Router React Server Components 文档：<https://reactrouter.com/how-to/react-server-components>
- React Router Changelog：<https://reactrouter.com/changelog>
- Rollup `onwarn` 配置：<https://rollupjs.org/configuration-options/#onwarn>
- Vite Build Options：<https://vite.dev/config/build-options.html>
