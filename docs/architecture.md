# NextE 架构

NextE 是原生 HarmonyOS NEXT（ArkTS/ArkUI）的 E-Hentai / ExHentai 客户端，包名为
`com.erosteam.nexte`。产品行为参考 `../eros_fe`，平台架构参考 `../V2Next`；参考项目只用于语义和写法，
当前 NextE 源码才是事实来源。

## 工程拓扑

当前 `build-profile.json5` 注册 10 个模块：`entry`、`shared`、`reader_enhancement`，以及
`home`、`gallery`、`search`、`reader`、`download`、`user`、`settings` 7 个 feature HAR。

```text
entry
├── shared ── reader_enhancement（third_party/reader-enhancement）
└── home / gallery / search / reader / download / user / settings
                         └── shared
```

- `entry` 是唯一导航壳和跨 feature 编排层。
- 7 个 feature 只依赖 `shared`，彼此不互相 import。
- `shared` 依赖 `reader_enhancement`，因此不是零依赖叶子。
- `reader_enhancement` 提供 native image decode、超分辨率和漫画视觉能力；它不是业务 feature。
- 默认产品的 `targetSdkVersion` 为 `26.0.0`、`compatibleSdkVersion` 为 `6.1.0(23)`；release 产品将
  target 提升到 `6.1.1(24)`，以 `build-profile.json5` 为准。

## 模块职责

| 模块 | 当前职责 |
| --- | --- |
| `entry` | `Index.ets` 导航壳、HDS 根布局、深链、跨 feature 路由与 Reader 全窗口 overlay。 |
| `home` | 画廊、订阅、热门、Toplist、历史和自定义 SubTab 列表。 |
| `gallery` | 详情、标签、评分、缩略图、评论、种子、归档和懒加载预览。 |
| `search` | 基础/高级搜索、搜索范围、标签补全和快速搜索。 |
| `reader` | 翻页/竖滑阅读、缩放、双页、自动翻页、音量键、预取、缩略图和视觉翻译入口。 |
| `download` | 画廊/归档下载队列、并发、续传和离线读。 |
| `user` | 远程收藏、本地收藏、My Tags、历史和用户资料。 |
| `settings` | 设置首页及 EH、布局、阅读、下载、翻译、同步、安全等子页。 |
| `shared` | 网络、解析器、模型、V2 state holder、持久化、缓存、主题、组件、服务、i18n 和诊断。 |
| `reader_enhancement` | 独立 native HAR；由 `shared` 暴露给 Reader/翻译服务。 |

## 导航与状态

`entry/src/main/ets/pages/Index.ets` 使用 `HdsNavigation` + `HdsTabs`。根 Tab 当前为五项：
画廊、收藏、排行、下载、设置；搜索是从标题栏进入的命名路由，不是根 Tab。根导航根据窗口策略在
`NavigationMode.Auto` 与 `NavigationMode.Stack` 间切换，并在宽屏显示 secondary placeholder；Reader
通过独立 overlay stack 覆盖全窗口。

命名路由由 `IndexRouteCoordinator`/`routerMap` 统一登记，详情、搜索、设置、评论、缩略图、登录和
Reader 辅助页均从这里进入。`EntryAbility` 接收 `/g/`、`/s/` 深链，写入 pending URL state，再由 Index
消费并调用 `EhRouteNavigator`。

所有产品代码使用 State Management V2：`@ComponentV2`、`@ObservedV2`、`@Trace`、`@Local`、`@Param`、
`@Monitor` 和项目 state holder。不要恢复 V1 decorator、适配器或随机 key 刷新；V1 inventory contract
是这个边界的机械门禁。

## 数据流与持久化

```text
EhHttpClient / EhApiService
  → HTML/JSON parser
  → Eh* model
  → feature ViewModel
  → AppStorageV2 / repository
  → @ComponentV2 UI
```

`shared` 负责 EH/ExHentai cookie、限流、解析、RDB、磁盘缓存、备份/同步边界、主题和本地化。图片
下载流式落盘；跨组件状态由明确 owner 的 holder 或命令总线传递。设置、评论翻译和漫画翻译分别拥有
自己的业务状态，不通过“全局当前 LLM”互相覆盖。

## 漫画翻译边界

Reader 主线的结果是视觉译制漫画页，不是原文/译文面板。provider-neutral 的源档案、上下文、缓存和
渲染产物可复用，但 Reader 不直接依赖厂商响应格式，也不从预取隐式触发模型调用。专业编辑、质检和
导出属于后续独立流程；详见[漫画翻译设计](manga-translation-design.md)。

## 维护原则

- 需要确认的 API、设备行为或远端协议以当前源码、脚本、官方文档和新鲜运行证据为准。
- 架构文档只记录稳定拓扑；任务状态、设备地址、截图目录和一次性结论留在对应计划或 Git 历史。
- 模块注册、依赖和导航变化后，先更新本文件，再运行对应的静态门禁。
