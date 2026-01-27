# 前端开发指南

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

```
mediask-fe/
├── apps/
│   ├── web/              # 管理端/医生端 (React SPA)
│   └── h5/               # 患者端 H5 (预留)
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
| 服务端状态 | React Query | 医院列表、排班、预约单 |
| 前端状态 | Zustand | token、用户信息、UI 状态 |

### 6.2 queryKey 规范

```ts
// 统一使用数组 + 结构化对象参数
export const qk = {
  hospitals: (params?: { keyword?: string }) => ['hospitals', params ?? {}] as const,
  schedules: (params: { doctorId: number; date: string }) => ['schedules', params] as const,
  appointmentsMy: (params: { status?: number }) => ['appointments', 'my', params] as const,
} as const;
```

### 6.3 失效策略

```ts
// 创建预约成功后
queryClient.invalidateQueries({ queryKey: qk.appointmentsMy({}) });
queryClient.invalidateQueries({ queryKey: qk.schedules({ doctorId }) });
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

### 8.3 新增患者端（H5）建议

- 新建：`apps/h5`
- 技术栈与 Web 保持一致（React 19 + TS + Vite + React Router v7 + Tailwind + Antd）
- 后续复用：把 API client / types / hooks 抽到 `packages/shared`
