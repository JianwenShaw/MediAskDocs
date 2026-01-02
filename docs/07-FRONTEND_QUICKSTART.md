# 前端快速开始（pnpm + Vite + React 19 + React Router v7 + Ant Design + Tailwind v4）

> 目标：前端不是重点，优先“能跑、能联调、可构建部署（静态 SPA）”。

## 1. 前置条件

- Node.js：建议 20 LTS
- pnpm：项目根目录已固定 `pnpm@10.27.0`

（可选）启用 corepack：

```bash
corepack enable
corepack prepare pnpm@10.27.0 --activate
pnpm -v
```

## 2. Monorepo 结构（当前约定）

- Web 管理端/医生端：`apps/web`
- 预留共享包：`packages/*`

工作区配置：`pnpm-workspace.yaml`

## 3. 安装依赖

在仓库根目录执行（推荐用 `-C` 指定子项目）：

```bash
pnpm install
```

如果你需要补装依赖：

```bash
pnpm -C apps/web add react-router axios antd
pnpm -C apps/web add -D tailwindcss @tailwindcss/vite
```

说明：
- `react-router`：使用 React Router v7（官网新口径，`BrowserRouter` 从 `react-router` 导入）
- `-D`：构建期工具放在 `devDependencies`

## 4. React Router v7（Declarative Mode）最小接入

入口文件（示例口径）：

```ts
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

## 5. Tailwind v4（Vite 插件）最小接入

### 5.1 Vite 插件

`apps/web/vite.config.ts`：

```ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
});
```

### 5.2 CSS 入口

`apps/web/src/index.css`：

```css
@import "tailwindcss";
```

## 6. 启动、构建与预览

```bash
pnpm -C apps/web dev
pnpm -C apps/web build
pnpm -C apps/web preview
```

构建产物：`apps/web/dist`

## 7. 部署要点（SPA 静态托管）

- 使用 `BrowserRouter` 时，Nginx/网关必须做 **history fallback**：非静态资源路径回退到 `index.html`，否则刷新子路由会 404。
- 若你无法控制服务器回退规则（某些 H5 场景），可改用 Hash 路由策略。


