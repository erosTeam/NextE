# NextE 架构

NextE 是原生 HarmonyOS NEXT(ArkTS/ArkUI)的 **E-Hentai / ExHentai 客户端**:移植 Flutter 应用 [eros_fe](https://github.com/3003h/Eros-FE) 的功能与交互,采用成熟 HarmonyOS 应用 V2Next 的工程架构与规范。SDK 26.0.0(API 26),包名 `com.erosteam.nexte`。

## 模块布局(Hvigor 多模块,镜像 V2Next 的 7 模块 HAR monorepo)

`build-profile.json5` `modules[]`(单向依赖:`entry → shared + 所有 feature`;`feature/* → shared`;feature 之间**绝不互相导入**;`shared` 是零依赖叶子):

```
            ┌──────────── entry (type: entry) ────────────┐
            │ 导航壳: Tabs + Navigation/NavPathStack      │
            │ EhRouteCoordinator(name→family 路由表)      │
            │ EntryAbility(深链、引导启动)                │
            │ 跨 feature 页: WebLogin / ImageSearch /     │
            │ Comment / AddTag / AllThumbnails / About    │
            └──┬────┬────┬────┬────┬────┬────┬────────────┘
  依赖 shared │    │    │    │    │    │    │ (file: 链接全部 7 个 feature)
  + 全部 feature ▼  ▼    ▼    ▼    ▼    ▼    ▼
  home  gallery  search  reader  download  user  settings   (各为 type: har)
    └──────┴───────┴───────┴────────┴────────┴──────┘
                       │ 每个 feature 仅依赖:
                       ▼
                 shared (type: har, 零依赖)
   network · parser · model · state · settings · components
   theme · services · utils · constants · cache · storage · diagnostics · i18n
```

### feature 模块职责(对照 V2Next / eros_fe)

| 模块 | 导出(barrel `Index.ets`) | 职责 | 对照 |
|---|---|---|---|
| **home** | `HomePage` `HomeViewModel` `GalleryListViewModel` | 多源画廊列表(画廊/关注/热门/Toplist/收藏/历史),共享列表脚手架,每源一个 VM | V2Next `feed` |
| **gallery** | `GalleryDetailPage` `GalleryDetailViewModel` | 画廊详情(封面/标签/评分/分类/操作行/缩略图/评论预览/懒加载预览) | V2Next `detail` |
| **search** | `GallerySearchPage` `SearchViewModel` `AdvancedSearchSheet` | 基础+高级搜索、`f_*` 构建、标签自动补全、快速搜索 | — |
| **reader** | `ReaderPage` `ReaderViewModel` | **独立 HAR**:翻页+竖滑双模、缩放矩阵、点击区、双页、自动翻页、音量键、预取、缩略图条——最重最高风险,隔离便于专项契约测试 | eros_fe view_controller(~1500 行) |
| **download** | `DownloadQueuePage` `DownloadViewModel` `ArchiverViewModel` | 队列/并发/续传状态机 + `@ohos.request.agent` 后台传输 + 离线读 | — |
| **user** | `FavoritesPage` `MyTagsPage` `UserProfileViewModel` | 远程 10 favcat + 本地收藏 + MyTags 管理 + 用户资料/限额 | V2Next `user` |
| **settings** | `SettingsPage` + 各子页 | ~14 个子设置页 + EH `uconfig` 同步 | V2Next `settings` |

`entry` 内部分层(同 V2Next):`pages/`(导航壳 + 跨 feature 页)、`model/`(各种 `Coordinator` 纯逻辑,保持 `build()` 轻薄)、`components/`、`viewmodel/`。全应用只有一个 `pages` profile = `["pages/Index"]`,其余页面均为命名路由,经 `stack.pushPathByName('GalleryDetail', params)` 压栈。

## shared 子系统

| 子系统 | 职责 | 关键文件(规划) |
|---|---|---|
| **network** | EH/ExHentai 的 Cookie 鉴权 + 抓取传输 | `EhHttpClient`(超时/退避重试/gzip/getText/302 探测)、`EhApiService`、`EhApiPhpService`(单 JSON POST `/api.php` 按 method 复用)、`EhCookieStore`+`EhCookieInterceptor`、`RateLimitTokenBucket`、`NetworkProxyRequest`、`EhErrorType` |
| **parser** | 内置正则/DOM 解析,每页型一个静态类,重解析走 TaskPool | `EhGalleryListParser`、`EhGalleryDetailParser`、`EhGalleryImageParser`、`EhImagePageParser`、`EhApiJsonParser`、`EhFavoritesParser`、`EhMyTagsParser`、`EhArchiverParser`… |
| **model** | 逐字段手写的 ArkTS 值类(禁解构/展开) | `EhGallery`(聚合根,~50 字段,merge/copy)、`EhGalleryImage`、`EhTag`、`EhComment`、`EhUser`、`EhFavcat`、`AdvanceSearch`、`RouteParams` |
| **state** | AppStorageV2 holder(`@ObservedV2`+`@Trace`+`connectXxx()`),命令总线 | `NavStackHolder`、`SiteModeState`、`AuthIdentityState`、`ListModeState`、`GalleryDetailActionState`、`ReaderActionState`、`PendingEhUrlState` |
| **theme** | 唯一设计令牌源 + EH 语义色 | `ThemeConstants`、`EhSemanticColors`(catColor/tagColorTagType/favColor) |
| **components** | 可复用 `@ComponentV2`(HDS 优先) | `GalleryCard*`、`GalleryListScaffold`(下拉刷新+触底分页+视图模式)、`EhThumbnail`、`TagChip`、`RatingBar`、`CommentRichText`… |
| **settings** | 各 `*Settings`(单 key + 单 apply 写者,双写 preferences + @Trace 镜像) | `SettingsBootstrap`、`SiteModeSettings`、`CookieJarSettings`、`ListModeSettings`、`ReadingSettings`、`DownloadSettings`… |
| **services** | 应用级单例的跨切流程 | `TagTranslationService`、`DownloadAgentService`、`ImageResolveService`、`AutoLockService` |
| **utils** | 纯工具 + 路由 | `EhUrlRouter`、`EhRouteNavigator`、`BreakpointSystem`/`FoldScreenUtil`、`DateUtils`、`HtmlEntityUtils` |
| **constants** | `EhConstants`(hosts/thumb/cats/509/UA/fallback IP)、`StorageKeys` | |
| **cache** | 图片 + 画廊元数据缓存(磁盘) | `ImageDiskCache`、`GalleryCacheRepository`、`ReaderResumeStore` |
| **storage** | RDB 本地重数据(schema 预留同步元数据/墓碑) | `LocalDataStore`、`HistoryRepository`、`ReadProgressRepository`、`DownloadTaskRepository` |
| **diagnostics** | `DiagnosticLogger`(hilog,脱敏) | `DiagnosticLogger`、`DiagnosticsRedactor` |
| **i18n** | `AppStrings`(基于语言态的覆盖 ResourceManager) | shared 不带本地化资源,字符串在 entry/ + AppScope/ |

## 数据流

`EhHttpClient` → `EhApiService`/`EhApiPhpService` → HTML/JSON **parser** → `Eh*` **model** → feature **ViewModel** → **AppStorageV2 holder** → `@ComponentV2` page。

漫画图片转录、跨页翻译、可选 OCR/布局和未来重绘使用独立的
[漫画翻译设计与演进指南](manga-translation-design.md)。其稳定边界是 provider-neutral 的画廊/页面
翻译文档；Reader 不直接依赖模型厂商响应格式，也不从图片预取隐式触发模型调用。

## 状态管理 V2(硬约束)

唯一允许的状态范式(见 [always-loaded-rules](agent-guides/always-loaded-rules.md))。canonical holder:

```ts
@ObservedV2
export class SiteModeState {
  @Trace isEx: boolean = false   // @Trace 字段即订阅点
}
const KEY: string = 'v2_siteMode'
export function connectSiteMode(): SiteModeState {
  return AppStorageV2.connect(SiteModeState, KEY, () => new SiteModeState())!
}
// 单写者 publish helper 改 holder;读者用 @Monitor('siteMode.isEx') 响应
```

跨组件信号 = 单写者命令总线(带时间戳的唯一 payload);高频状态(如 reader 当前页 index)隔离到独立 holder 避免观察者抖动。

## 导航

`entry/pages/Index.ets` 是导航壳。**M0 用原生 `Tabs` + `Navigation`/`NavPathStack`(零依赖,保证编译绿)**,4 个底栏(首页/搜索/收藏/我的);命名路由 `GalleryDetail`/`Reader`/`Download` 经 `routerMap` 注册。**M1 升级为 HDS(`HdsNavigation`+`HdsTabs`,来自 `@kit.UIDesignKit`,与 V2Next 一致,已确认 SDK 26 内置可用、无需额外依赖)。** `EntryAbility` 解析 `/g/` `/s/` 深链 → `publishPendingEhUrl` → `Index` 经 `@Monitor` 消费 → `EhRouteNavigator` 压栈。
