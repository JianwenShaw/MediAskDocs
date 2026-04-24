# 前端架构与开发规范

## 1. 核心目标与执行边界

前端开发现阶段（P0）的唯一核心目标是**支撑核心医疗主链路的完整闭环演示**，而非建设大而全的前端平台。

- **核心主链路**：`患者登录 -> AI 问诊 -> 智能导诊 -> 挂号 -> 医生接诊 -> 病历/处方录入 -> 审计查询`
- **端侧形态边界**：
  - **患者端**：移动端 H5 形态（兼容微信内置浏览器等环境），承接 AI 交互与挂号流转。
  - **医生端/管理端**：桌面端 Web SPA 形态，面向高信息密度的表单、表格及病历管理场景。
- **范围控制**：当前阶段不单独建设小程序、不引入 React Native，暂不开发复杂排班或精细化权限配置树。

---

## 2. 技术栈选型

整体采用 React 体系，通过工具链收敛提升开发效率，保障工程质量。

| 技术模块 | 核心选型 | 版本 | 选型考量与规范 |
| :--- | :--- | :--- | :--- |
| **核心框架** | **React** | 19 | 采用最新并发特性；所有新组件均采用 Functional Component + Hooks。 |
| **语言** | **TypeScript** | 5.x | 强制开启严格模式，保障 DTO 与内部状态的强类型约束。 |
| **构建工具** | **Vite** | - | 极速冷启动与 HMR，生产环境基于 Rollup 构建。 |
| **路由管理** | **React Router**| 7.x | 采用声明式路由，支持嵌套路由与 Loader/Action 模式。 |
| **UI 框架** | **Ant Design** | 6.0 | 仅用于**医生/管理端**，统一中后台视觉规范，提升表单/表格开发效率。 |
| **样式方案** | **Tailwind CSS**| 4.x | 全局通用的原子化 CSS，用于**患者端**定制化 UI 与各端结构布局。 |
| **服务端状态** | **React Query** | - | 负责所有 API 请求的缓存、轮询、失效重刷（如 AI 会话、挂号记录）。 |
| **客户端状态** | **Zustand** | - | 轻量级全局状态管理，仅用于 UI 状态、登录 Token、当前用户信息等。 |

---

## 3. 工程架构设计

推荐采用 Monorepo 组织代码，实现跨端类型与请求库复用。P0 阶段可先在一个目录下按模块划分，后续平滑演进。

### 3.1 目录结构

```text
mediask-fe/
├── apps/
│   ├── backoffice-web/   # 医生端与管理员端 (React SPA + AntD)
│   └── patient-h5/       # 患者端 H5 (React SPA + Tailwind)
├── packages/
│   ├── api-client/       # 基于原生 fetch 的统一请求封装与拦截器
│   └── shared-types/     # 前后端对齐的 TypeScript DTO 与枚举
├── pnpm-workspace.yaml
└── package.json
```

### 3.2 路由与模块规划

前端路由必须严格匹配业务域，以下为推荐的路由结构设计：

**患者端 (Patient H5)**
- `/login`：鉴权与身份确认。
- `/ai/session/:sessionId`：核心问诊交互（流式对话、引用展示）。
- `/triage/result/:sessionId`：智能导诊结果（根据风险等级分流）。
- `/triage/high-risk/:sessionId`：高风险拦截与紧急就医引导。
- `/registrations/new` & `/registrations`：挂号办理与历史查询。

**医生/管理端 (Backoffice Web)**
- `/workbench`：医生工作台门户。
- `/encounters` & `/encounters/:id`：待接诊列表与接诊工作台（含 AI 摘要）。
- `/emr/:encounterId`：结构化病历编辑。
- `/prescriptions/:encounterId`：电子处方开立。
- `/audit`：管理端系统操作审计与数据访问日志查询。
- `/forbidden`：已登录但无医生/管理员后台访问权限时的稳定拦截页。

---

## 4. 核心业务与技术实现路径

### 4.1 AI 问诊与状态流转机制

前端必须严谨处理 AI 的输出结果，将大模型能力与真实医疗流程（挂号、就医）闭环：

1. **流式展示**：前端仍只访问 Java；Java 可调用 Python `/api/v1/query/stream` 并转发 SSE，但前端只能把 `delta` 当作展示文本。
2. **结构化承接**：一切业务动作以同步响应或 SSE `final` 事件里的结构化 `triageResult.nextAction` 为准，前端禁止解析自然语言决策，`delta` 文本不得参与状态判断。
3. **风险分流策略**：
   - `low + allow`：展示常规诊疗建议与推荐科室，提供挂号入口。
   - `medium + caution`：高亮免责声明与保守建议，引导至线下医院挂号。
   - `high + refuse`：立即中断问答，强制跳转高风险页（提供紧急呼叫或急诊引导）。

### 4.2 状态管理机制

分离服务端状态与客户端状态，避免全局 Store 臃肿。

**Query Key 规范 (React Query)**
统一采用数组+结构化对象的参数格式，便于精准粒度的缓存失效控制。
```typescript
export const queryKeys = {
  aiSession: (sessionId: string) => ['ai', 'session', sessionId] as const,
  registrations: (params: { status?: string }) => ['registrations', 'list', params] as const,
} as const;
```

**缓存失效策略示例**
挂号动作完成后，自动触发相关列表数据的更新：
```typescript
queryClient.invalidateQueries({ queryKey: queryKeys.registrations({}) });
```

### 4.3 安全性与异常体验处理 (Security & Error Handling)

为了保障核心主链路的稳定性与患者数据安全，前端必须严格遵守以下规范：

1. **AI 流式输出的 XSS 防护（最高优先级）**
   - AI 生成的 Markdown 内容包含极高的 XSS 注入风险。
   - **绝对禁止**在 React 中直接使用原生 `dangerouslySetInnerHTML` 渲染 AI 输出内容。
   - **规范**：必须采用安全的 Markdown 渲染方案，默认仅渲染受限 Markdown 子集，禁止将 AI 输出中的原始 HTML 直接注入 DOM。
   - **推荐实现**：优先使用 `react-markdown` 一类默认不执行原始 HTML 的渲染方案；只有在业务明确要求支持原始 HTML 时，才允许额外引入严格的白名单消毒（如 `DOMPurify`）。

2. **基于原生 Fetch 的全局鉴权与拦截器**
   - **禁用 Axios**，统一采用浏览器原生的 `fetch` API 手动封装 HTTP Client（即 `api-client` 包）。
   - **请求拦截 (Request)**：封装层需自动从 Zustand 状态管理中读取 Token，并统一注入到请求头的 `Authorization: Bearer <token>` 中。
   - **响应拦截 (Response)**：集中处理 HTTP 状态码。若遇到 `401 Unauthorized`（Token 失效），需自动清理本地用户信息并联动 React Router 跳转至 `/login` 页；遇到 `403 Forbidden` 则统一弹出无权限提示，剥离业务组件的鉴权心智负担。
   - **后台角色边界**：`backoffice-web` 只面向 `DOCTOR` 和 `ADMIN`。若用户已认证但角色不属于后台可用角色（如 `PATIENT`），前端必须进入稳定的 `/forbidden` 页面，不能重定向回 `/login`，更不能形成 `/` 与 `/login` 的循环跳转。
   - **启动校验失败**：若浏览器存在缓存 Token，应用启动后调用 `/api/v1/auth/me`。当返回 `401` 时清理登录态并回到 `/login`；当返回 `5xx`、网络错误等非 `401` 异常时，必须退出加载态并展示初始化失败界面，禁止永久停留在 loading spinner。

3. **流式断网与 Error Boundary（防白屏机制）**
   - **AI 对话异常兜底**：在 AI 流式问诊过程中如果发生网络中断或接口 5xx 报错，页面不得直接崩溃或跳出。UI 层面应保留已生成的对话历史，并在底部提供局部的「重新生成/网络重试」按钮。
   - **全局 Error Boundary**：在路由根节点和各个核心模块（如医生工作台、接诊详情）顶层包裹 React `Error Boundary`。一旦发生不可预期的组件级渲染崩溃，立刻捕获错误并展示优雅的 Fallback UI（例如“页面开小差了，点击刷新”），坚决杜绝用户看到纯白屏现象。

---

## 5. 开发与部署指南

### 5.1 环境基线

- **Node.js**: 24 LTS
- **包管理器**: pnpm (>= 10.33.0)

### 5.2 Backoffice API 地址配置

`apps/backoffice-web` 的认证与后续业务接口默认通过 `VITE_API_BASE_URL` 指向 Java 后端。

本地联调时，必须确保该变量已配置到真实后端地址；否则浏览器会把 `/api/v1/auth/login`、`/api/v1/auth/me` 等请求发到前端开发服务器自身，常见现象是：

- `POST /api/v1/auth/login` 返回 `404`
- 响应体为空
- 登录页提示接口不存在或空响应

推荐做法：

- 在 `apps/backoffice-web/.env.development` 中配置 `VITE_API_BASE_URL=http://localhost:8989`
- `staging / production` 分别在 `.env.staging`、`.env.production` 中配置对应后端域名
- 所有前端可见环境变量都必须使用 `VITE_` 前缀

示例：

```env
VITE_API_BASE_URL=http://localhost:8989
```

说明：

- 若未配置该变量，当前实现会退回同源请求，不适合本地前后端分离联调

### 5.3 常用命令

```bash
# 安装依赖 (根目录)
pnpm install

# 启动各端开发服务
pnpm -C apps/patient-h5 dev
pnpm -C apps/backoffice-web dev

# 生产环境构建
pnpm -C apps/backoffice-web build
```

### 5.4 Nginx 部署配置要求

单页应用 (SPA) 配合 `BrowserRouter`（History 模式）部署时，必须配置 **history fallback**，将所有未命中静态资源的路由重定向至 `index.html`。

```nginx
server {
    listen 80;
    server_name example.com;
    root /var/www/mediask-fe/dist;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```
