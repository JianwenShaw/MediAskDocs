# 前端工程搭建过程回顾（截至当前：已完成 Web 端）

> 用途：把你已经做过的操作固化成可复现步骤，便于接下来按同样思路新增患者端（H5）。

## 1. 仓库结构与包管理（pnpm workspace）

### 1.1 根目录 `package.json`

- 已设置：
  - `private: true`
  - `packageManager: pnpm@10.27.0`

作用：
- `private: true`：防止误发布根包到 npm
- `packageManager`：固定团队 pnpm 版本，减少 lockfile/依赖差异

### 1.2 工作区 `pnpm-workspace.yaml`

已配置：

```yaml
packages:
  - "apps/*"
  - "packages/*"
```

含义：`apps/*` 放应用（Web/H5），`packages/*` 放共享包（后续可抽 axios client、types 等）。

## 2. Web 端工程（管理员/医生端）

### 2.1 创建 Vite + React + TS 工程

在仓库根目录执行：

```bash
mkdir -p apps
pnpm create vite apps/web --template react-ts
pnpm install
```

### 2.2 安装核心依赖

在 `apps/web` 安装：

```bash
pnpm -C apps/web add react-router axios antd
```

说明：
- 选择 **React Router v7**（官网新口径）：从 `react-router` 导入 `BrowserRouter`

### 2.3 安装并接入 Tailwind（v4 + Vite 插件）

安装（devDependencies）：

```bash
pnpm -C apps/web add -D tailwindcss @tailwindcss/vite
```

配置 `apps/web/vite.config.ts`（在 `react()` 之外增加 `tailwindcss()`）：
- `plugins: [react(), tailwindcss()]`

配置 `apps/web/src/index.css`（作为全局样式入口）：

```css
@import "tailwindcss";
```

### 2.4 React Router v7 最小接入

已在 `apps/web/src/main.tsx`：
- 用 `BrowserRouter` 包裹 `App`
- 导入来自 `react-router`

### 2.5 清理 Vite 模板页面效果

你的目标是不要 Vite 默认模板样式，因此做了：
- 删除 `apps/web/src/App.css`
- 重写 `apps/web/src/App.tsx` 为最小页面（Antd + Tailwind 示例）

### 2.6 构建验证

已验证构建成功：

```bash
pnpm -C apps/web build
```

## 3. 当前状态检查清单（你现在应该具备的能力）

- ✅ `pnpm install` 可在根目录完成依赖安装
- ✅ `pnpm -C apps/web dev` 可启动 Web 端开发服务
- ✅ `pnpm -C apps/web build` 可产出 `apps/web/dist`（静态 SPA 产物）
- ✅ Tailwind v4 可用（写 className 生效）
- ✅ Ant Design 可用（组件可渲染）
- ✅ React Router v7 可用（`BrowserRouter` 已接入）

## 4. 下一步：新增患者端（H5）的建议目录

- 建议新建：`apps/h5`
- 与 Web 保持一致的技术栈（React 19 + TS + Vite + React Router v7 + Tailwind + Antd）
- 后续若要复用：把 `api client / types / hooks` 抽到 `packages/shared`


