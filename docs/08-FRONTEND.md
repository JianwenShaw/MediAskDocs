# 前端开发指南

> 执行边界说明：前端 `P0` 目标是支撑主链路演示，不是先完成完整前端平台化建设。若时间有限，可先用单应用打通患者主链路，再扩展医生端与共享包。

## 1. 技术选型

| 技术 | 版本 | 说明 |
|------|------|------|
| React | 19 | 并发模式优化用户体验 |
| TypeScript | 5.x | 强类型约束 |
| Vite | - | 极速冷启动，秒级热更新 |
| Ant Design | 6.0 | 企业级中后台 UI 组件库 |
| Tailwind CSS | 4.x | 原子化 CSS |
| Zustand | - | 轻量级状态管理 |
| React Query | - | 服务端状态缓存 |
| React Router | v7 | 声明式路由 |

## 2. Monorepo 结构

> 以下是推荐目标形态，不是 `P0` 前置条件。`P0` 完全可以先从单个应用启动，跑通主链路后再整理为 Monorepo。

```
mediask-fe/
├── apps/
│   ├── web/              # 管理端/医生端 (React SPA)
│   └── h5/               # 患者端 H5 (P0 主链路入口)
├── packages/
│   └── shared/           # 共享包 (API client, types, hooks)
├── pnpm-workspace.yaml
└── package.json
```

### 2.1 工作区配置

```yaml
# pnpm-workspace.yaml
packages:
  - "apps/*"
  - "packages/*"
```

### 2.2 P0 页面与接口范围

前端开发以毕设主链路为准，不按“完整 HIS 后台”平铺展开。

| 端 | 页面/模块 | 目标 | 对应接口 |
|----|-----------|------|---------|
| **患者 H5** | 登录/身份确认 | 进入个人数据域 | `/api/v1/auth` |
| **患者 H5** | AI 问诊会话页 | 输入症状、展示流式回答、引用与风险提示 | `/api/v1/ai/chat`、`/api/v1/ai/chat/stream` |
| **患者 H5** | 科室/门诊推荐结果页 | 承接 AI 导诊结论与下一步动作 | `/api/v1/ai/sessions/{id}/triage-result`、`/api/v1/ai/sessions/{id}/registration-handoff`、`/api/v1/clinic-sessions` |
| **患者 H5** | 挂号提交与我的挂号 | 创建并查看 `registration_order` | `/api/v1/registrations` |
| **医生 Web** | 登录与工作台首页 | 进入接诊主流程 | `/api/v1/auth`、`/api/v1/encounters` |
| **医生 Web** | 接诊列表/详情 | 查看挂号记录与 AI 摘要 | `/api/v1/registrations`、`/api/v1/encounters`、`/api/v1/encounters/{id}/ai-summary` |
| **医生 Web** | 病历编辑页 | 创建/修改病历与诊断 | `/api/v1/emr` |
| **医生 Web** | 处方编辑页 | 创建处方与处方项 | `/api/v1/prescriptions` |
| **管理员/审计端** | 审计查询页（最小版） | 展示审计与访问日志 | `/api/v1/audit` |

P0 不要求前端先做完整排班工作台、复杂权限配置树、P2 级观测大盘。

AI 外部接口字段口径以 [10A-JAVA_AI_API_CONTRACT.md](./10A-JAVA_AI_API_CONTRACT.md) 为准；前端不要直接绑定 Python 内部响应结构。

### 2.3 建议路由收敛

| 端 | 路由 | 说明 |
|----|------|------|
| **患者 H5** | `/login` | 登录 |
| **患者 H5** | `/ai/session/:sessionId` | AI 问诊 |
| **患者 H5** | `/triage/result/:sessionId` | 导诊结果与引用 |
| **患者 H5** | `/triage/high-risk/:sessionId` | 高风险拒答/紧急就医提示 |
| **患者 H5** | `/registrations/new` | 挂号提交 |
| **患者 H5** | `/registrations` | 我的挂号 |
| **医生 Web** | `/workbench` | 工作台 |
| **医生 Web** | `/encounters` | 接诊列表 |
| **医生 Web** | `/encounters/:id` | 接诊详情 |
| **医生 Web** | `/emr/:encounterId` | 病历编辑 |
| **医生 Web** | `/prescriptions/:encounterId` | 处方编辑 |
| **管理员/审计端** | `/audit` | 审计查询 |

### 2.4 AI 页面状态与承接规则

前端 `P0` 必须把 AI 输出结果和后续业务动作连接起来，而不是只展示一段文本。

| 风险结果 | 页面表现 | 下一步 |
|----------|----------|--------|
| `low + allow` | 展示答案、引用、推荐科室 | 允许继续问诊或去挂号 |
| `medium + caution` | 突出免责声明与保守建议 | 默认引导到导诊结果页和挂号入口 |
| `high + refuse` | 不继续普通问答 | 跳转高风险页，展示紧急就医/人工求助提示 |

结构化字段以 `triageResult.nextAction` 为准，不要在前端自行猜测风险分支。

## 3. 快速开始

### 3.1 环境要求

- Node.js: 20 LTS
- pnpm: 10.27.0（项目根目录固定版本）

```bash
# 启用 corepack（可选）
corepack enable
corepack prepare pnpm@10.27.0 --activate
```

### 3.2 安装依赖

```bash
# 根目录安装所有依赖
pnpm install

# 为特定应用安装依赖
pnpm -C apps/web add react-router axios antd
pnpm -C apps/web add -D tailwindcss @tailwindcss/vite
```

### 3.3 启动开发服务

```bash
# 启动 Web 端
pnpm -C apps/web dev

# 构建生产产物
pnpm -C apps/web build

# 预览构建产物
pnpm -C apps/web preview
```

## 4. React Router v7 接入

### 4.1 入口文件

```tsx
// apps/web/src/main.tsx
import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router";
import App from "./App";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </React.StrictMode>
);
```

### 4.2 路由配置

```tsx
// apps/web/src/App.tsx
import { Routes, Route } from "react-router";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";

function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route path="/" element={<Dashboard />} />
    </Routes>
  );
}
export default App;
```

## 5. Tailwind CSS v4 接入

### 5.1 Vite 配置

```ts
// apps/web/vite.config.ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
});
```

### 5.2 CSS 入口

```css
/* apps/web/src/index.css */
@import "tailwindcss";
```

## 6. 状态管理

### 6.1 状态归属原则

| 状态类型 | 工具 | 示例 |
|---------|------|------|
| 服务端状态 | React Query | AI 会话、门诊场次、挂号单、接诊记录 |
| 前端状态 | Zustand | token、用户信息、UI 状态 |

### 6.2 queryKey 规范

```ts
// 统一使用数组 + 结构化对象参数
export const qk = {
  aiSession: (sessionId: string) => ['ai', 'session', sessionId] as const,
  clinicSessions: (params: { departmentId?: number; date?: string }) => ['clinic-sessions', params] as const,
  registrationsMy: (params: { status?: string }) => ['registrations', 'my', params] as const,
  encountersMine: (params?: { status?: string }) => ['encounters', 'mine', params ?? {}] as const,
} as const;
```

### 6.3 失效策略

```ts
// 创建挂号成功后
queryClient.invalidateQueries({ queryKey: qk.registrationsMy({}) });
queryClient.invalidateQueries({ queryKey: qk.clinicSessions({ departmentId, date }) });
```

## 7. 部署要点

### 7.1 SPA 静态托管

- 构建产物：`apps/web/dist`
- 使用 `BrowserRouter` 时，Nginx 必须配置 **history fallback**：

```nginx
location / {
  try_files $uri $uri/ /index.html;
}
```

### 7.2 部署命令

```bash
# 生产构建
pnpm -C apps/web build

# 部署 dist 目录到 Nginx 或对象存储
```

## 8. 工程搭建历史

> 已完成的操作清单，便于复现或新增患者端时参考

### 8.1 已完成步骤

1. **创建 Vite + React + TS 工程**
   ```bash
   mkdir -p apps
   pnpm create vite apps/web --template react-ts
   ```

2. **安装核心依赖**
   ```bash
   pnpm -C apps/web add react-router axios antd
   ```

3. **安装 Tailwind v4**
   ```bash
   pnpm -C apps/web add -D tailwindcss @tailwindcss/vite
   ```

4. **配置 React Router v7**
   - `BrowserRouter` 从 `react-router` 导入

5. **验证构建**
   ```bash
   pnpm -C apps/web build
   ```

### 8.2 当前状态检查

- [x] `pnpm install` 根目录完成依赖安装
- [x] `pnpm -C apps/web dev` 可启动开发服务
- [x] `pnpm -C apps/web build` 可产出 dist 静态产物
- [x] Tailwind v4 可用（className 生效）
- [x] Ant Design 可用（组件可渲染）
- [x] React Router v7 可用

### 8.3 患者端（H5）建议

- 技术栈与 Web 保持一致（React 19 + TS + Vite + React Router v7 + Tailwind + Antd）。
- 患者端优先承接 AI 问诊、导诊结果、挂号提交、我的挂号四条主链路页面。
- API client / types / hooks 优先抽到 `packages/shared`，避免 Web/H5 双份维护。
