# 🌍 Backoffice 国际化 (i18n) 实施方案

## 1. 目标与范围
当前 `backoffice-web` 是一个基于 React Router 7 和 Ant Design 的纯客户端单页应用。针对只支持中英文（zh / en）的需求，制定本国际化（i18n）实施方案。

## 2. 技术选型
*   **核心库**: `i18next` + `react-i18next` (React 社区最成熟的方案)。
*   **持久化与探测**: `i18next-browser-languagedetector` (用于记住用户上次选择的语言或检测浏览器语言)。
*   **Ant Design 集成**: 结合 Ant Design 自带的 `ConfigProvider`，同步切换组件（如日期选择器、分页器、表格空状态等）的内置多语言。

## 3. 目录结构设计
在 `apps/backoffice-web/src` 下新建 `i18n` 目录，按业务模块划分命名空间，避免单文件臃肿：

```text
src/
  ├── i18n/
  │    ├── index.ts          # i18next 初始化与核心配置
  │    └── locales/          # 翻译字典文件目录
  │         ├── zh.json      # 中文文案 (默认)
  │         └── en.json      # 英文文案
```

*建议的 JSON 结构:*
```json
{
  "common": {
    "confirm": "确定",
    "cancel": "取消",
    "save": "保存"
  },
  "menu": {
    "workbench": "工作台",
    "encounters": "接诊记录"
  }
}
```

## 4. 核心实施步骤

### 步骤一：安装依赖
在 Workspace 中为 backoffice 安装所需依赖：
```bash
pnpm add i18next react-i18next i18next-browser-languagedetector -F @mediask/backoffice-web
```

### 步骤二：初始化配置 (`src/i18n/index.ts`)
配置 `i18next`，设置 `fallbackLng: 'zh'`，加载本地的 `zh.json` 和 `en.json`，并注入到 react-i18next 中。确保在 `main.tsx` 最早处引入该初始化文件。

### 步骤三：Ant Design 全局配置桥接
在根组件或 `AppLayout` 中引入 Ant Design 的语言包 (`zh_CN` 和 `en_US`)。
监听 `i18next` 的语言变化，动态切换 `<ConfigProvider locale={...}>` 的值，确保 Antd 自带组件与业务语言一致。

### 步骤四：开发语言切换器 (Language Switcher)
在 `AppLayout` 的顶栏 (Header) 添加一个语言切换按钮或下拉菜单。点击时调用 `i18n.changeLanguage('en')` 并自动更新整个应用的 UI。这会自动触发 react-i18next 的重新渲染机制。

### 步骤五：渐进式文本替换
遍历现有的主要页面组件（如 `router.tsx` 中的菜单名，`LoginPage`, `WorkbenchPage`, `EncountersPage` 等）：
1.  提取硬编码的中文字符串。
2.  将其写入 `zh.json` 并翻译后写入 `en.json`。
3.  使用 `const { t } = useTranslation()` 钩子将 UI 中的文本替换为 `t('namespace.key')`。

## 5. 后续注意事项与最佳实践

*   **日期格式化 (Day.js)**: 由于 Antd 6.x 默认集成 Day.js，切换语言时也需要同步调用 `dayjs.locale('zh-cn' | 'en')`，以确保业务代码中通过 Day.js 格式化的日期（如 `YYYY-MM-DD dddd`）呈现正确的语言环境。
*   **API 接口国际化 (可选)**: 在 Axios/Fetch 的拦截器中，可以统一在请求 Header (`Accept-Language: zh-CN` 或 `en-US`) 中带上当前语言标识，以便后端（如果支持）返回对应语言的错误提示信息。
*   **HTML Lang 属性**: 切换语言时，除了更新 React 状态，也应动态更新 `document.documentElement.lang`，以利于可访问性 (a11y) 和浏览器原生翻译工具。
