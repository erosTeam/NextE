# NextE 路线图

原生 HarmonyOS NEXT E-Hentai 客户端,移植 eros_fe 功能、采用 V2Next 架构。分阶段交付,每阶段可验证。

> 优先级口径(对照 eros_fe 功能集):**P0** 浏览列表 + 画廊详情 + 阅读器 + Cookie 登录 + 表/里站切换;**P1** 搜索/高级搜索/标签翻译/收藏/EH 设置;**P2** 下载/归档/评论/历史;**P3** WebDAV 同步/屏蔽/生物锁/EPUB/搜图/种子。

---

## ✅ M0 — 脚手架、构建、签名绿灯 **(已完成并验证)**

空的 9 模块 HAR monorepo,能构建、能(待签名物料就绪后)签名安装、启动到占位壳。CI + V1 装饰器 + 模块一致性 + i18n 门禁通过。

**已交付且验证**:
- 根 `build-profile.json5`(targetSdk 26.0.0 / compatibleSdk 6.1.0(23) / `strictMode.useNormalizedOHMUrl`),`modules[]` = entry + shared + home/gallery/search/reader/download/user/settings
- `oh-package.json5`(modelVersion 6.1.1,name `nexte`,version 1.0.1)+ 各模块 `oh-package.json5`(`file:` 依赖);`hvigorfile.ts`/`hvigorconfig.ts`/`hvigor/hvigor-config.json5`/`.gitignore`
- `AppScope/app.json5`(bundleName `com.erosteam.nexte`,vendor `erosTeam`,versionCode 2,label `$string:app_name`,无云同步)
- `entry/module.json5`(type entry,EntryAbility,INTERNET+GET_NETWORK_INFO+VIBRATE,`/g/`+`/s/` viewData 深链,`$profile:main_pages`)
- 最小 `EntryAbility.ets`(全屏、透明栏、`SettingsBootstrap` 引导、`AppStrings.init`、hilog)+ `Index.ets` 壳(原生 Tabs+Navigation,4 占位页,3 命名路由)
- 各 feature HAR:`module.json5`(har)、`build-profile.json5`、`hvigorfile.ts`(harTasks)、`Index.ets` barrel(占位页导出)
- `shared` HAR 骨架:`ThemeConstants`、`AppStrings`、`StorageKeys`、`EhConstants`、`DiagnosticLogger`、`NavStackHolder`、`PendingEhUrlState`、`SettingsBootstrap`、`EhUrlRouter`
- `dev.sh` + `scripts/sign.py` + `scripts/dev.env.sample`(包名 `com.erosteam.nexte`,复用账号级证书,需单独签发 `com.erosteam.nexte.p7b` profile)
- AppScope + entry `resources/<locale>/element/string.json`(base/zh_CN/en_US/ja_JP,key 集一致)
- `scripts/test_v1_decorator_inventory_contract.mjs` + `test_version_consistency_contract.mjs` + `check_i18n_duplicates.py`
- `docs/agent-guides/harmonyos-default.md` + `always-loaded-rules.md`

**验证结果**:`hvigorw assembleHap` → BUILD SUCCESSFUL(unsigned HAP 产出);V1 装饰器 0;9 模块一致;4 语言 key 一致。

> 待办(需用户提供):为 `com.erosteam.nexte` 签发调试 Provisioning Profile 后,`bash dev.sh` 可完成签名 + 真机安装。M0 的可验证门禁是 unsigned 构建(已绿)。

---

## M1 — 网络 + parser 核心 + 浏览列表

Tab 首页渲染**实时、分页、可切视图模式**的画廊列表(表站匿名)。打通 `HttpClient→ApiService→parser→model→ViewModel→@ComponentV2`。先把导航壳升级为 HDS(`HdsNavigation`+`HdsTabs`)。

- `shared/constants/EhConstants` 补全(cats 位掩码、favcat 色表、REG_509、fallback IP)+ `getBaseUrl()`
- `shared/network`:`EhHttpClient`(超时/重试/gzip)、`EhApiService`(GET 列表)、`RateLimitTokenBucket`、`EhCookieStore`+`EhCookieInterceptor`(nw=1,暂无鉴权)、`NetworkTypes`
- `shared/parser`:`EhGalleryListParser`(行/gid-token 正则/sprite 评分/favcat/分页,TaskPool worker)、`inline_set=dm_l` 重试;`EhApiJsonParser.gdata`(批量 25 enrich)
- `shared/model`:`EhGallery`、`EhTag`、`GalleryList`(手写 ArkTS 类)
- `shared/components`:`GalleryCard*` + `GalleryListScaffold`(下拉刷新 + 触底分页 + 5 视图模式 List/WaterFlow/Grid)+ `EhThumbnail`
- `shared/state`/`settings`:`ListModeState`/`SiteModeState`/`ListModeSettings`/`SiteModeSettings` + `SettingsBootstrap` 恢复
- `shared/theme`:`ThemeConstants` 补全 + `EhSemanticColors`
- `feature/home`:`HomePage`(画廊/关注/热门/Toplist 子 tab)+ `GalleryListViewModel`(LazyForEach 数据源置于 @Trace 之外)
- **HDS 壳升级**(`@kit.UIDesignKit`)+ 网络可达层:DoH(`cloudflare-dns.com`)解析真实 IP + fallback IP 直连 + 用户代理/VPN 支持(**不做域名前置**——已废弃)
- 契约测试:`test_gallery_list_parser_contract.mjs`、`test_network_client_contract.mjs`

## M2 — 画廊详情 + 阅读器

列表项 → 详情(封面/标签/评分/缩略图/操作,懒加载预览)→ READ 打开阅读器(翻页+竖滑、缩放、点击区、页码条、预取)。核心 浏览→详情→阅读 闭环。

- `shared/parser`:`EhGalleryDetailParser` + `EhGalleryTagsParser` + `EhGalleryImageParser`(3 布局)+ `EhImagePageParser` + apiuid/apikey 抓取
- `shared/services/ImageResolveService`(showKey/showpage 快路径,509 `nl=` 换源)+ `shared/cache`(`ImageDiskCache`/`ReaderResumeStore`/`GalleryCacheRepository`)
- `feature/gallery`:`GalleryDetailPage`(折叠封面标题 + 头/标签/评分/分类/操作行/缩略图/评论预览/懒加载)+ `GalleryDetailViewModel`;item 或 `/g/{gid}/{token}` 双入口
- `feature/reader`:`ReaderPage` + `ReaderViewModel` —— Swiper(横向,RTL 翻转)+ List(竖向)、捏合+双击缩放矩阵、点击区(左右翻页/中切 chrome)、页码条 + 同步缩略图条、沉浸全屏、per-gid 续读、N 页预取
- `entry`:`EhRouteCoordinator` family 表、`ReaderActionState`/`GalleryDetailActionState` 命令总线、深链 + 剪贴板 `/g/` 检测
- **阅读器手势-缩放 + 翻页共存 spike**(单 Swiper page 内先验证)
- 契约测试:`test_gallery_detail_parser_contract.mjs`、`test_reader_paging_contract.mjs`、`test_image_resolve_contract.mjs`

## M3 — 登录 + Cookie + 里站 + 收藏 + 搜索

WebView Cookie 登录抓取 `ipb_*`/`igneous`,解锁里站切换,远程 favcat + 本地收藏可用,基础+高级搜索 + 标签补全上线。

- `entry/pages/WebLoginPage`(`@ohos.web.webview` 登录 forums,经 `WebCookieManager` 抓取 → 镜像进 `EhCookieStore`)+ 手动粘贴 cookie 兜底;`AuthIdentityState.isLogin` 镜像
- `shared/network`:拦截器注入完整鉴权包;`getExIgneous`(已登录 GET uconfig.php);sad-panda 检测
- `shared/settings/CookieJarSettings`(持久化敏感包,脱敏)+ 站点切换 UI(登录+igneous 门禁)
- `shared/parser`:`EhFavoritesParser` + `EhMyTagsParser` + `EhAdvanceSearchParser`;addfav POST + 302 成功检测
- `feature/user`:`FavoritesPage`(10 favcat tab + 选择对话框 + 收藏备注/排序)+ `LocalFavRepository` + `MyTagsPage`(关注/隐藏/颜色/权重,详情长按快速加)
- `feature/search`:`GallerySearchPage`(分类 chip + `f_*` 高级筛选 sheet + `AdvanceSearch` 编码)+ 标签补全(tagsuggest / 本地标签库 debounce)+ `QuickSearchRepository`
- `shared/services/TagTranslationService`(下载 + gunzip `db.raw.json.gz` → RDB,ghproxy 兜底)驱动中文标签显示与补全
- `shared/storage`:`LocalDataStore` RDB + `HistoryRepository`/`ReadProgressRepository`(**schema 现在就带墓碑元数据**,为 M6 WebDAV 同步预留)
- 契约测试:`test_auth_cookie_contract.mjs`、`test_favorites_contract.mjs`、`test_search_param_contract.mjs`

## M4 — 下载 + 归档 + 离线阅读

队列式逐画廊下载(暂停/续传/删除、原图选项)经 `@ohos.request.agent` 后台存活;归档 zip 下载可在阅读器读;已下载画廊可离线读。

- `feature/download`:`DownloadQueuePage` + `DownloadViewModel`(队列/并发/续传状态机)+ `ArchiverViewModel`
- `shared/services/DownloadAgentService`(`@ohos.request.agent` OS 托管后台下载,携带 EH cookie + per-image token,509 重试)+ `DownloadTaskRepository`
- `shared/parser/EhArchiverParser`(请求归档/轮询/下载 zip)+ `@ohos.zlib` 读 zip
- `ImageResolveService` 扩展:从下载目录与归档 zip 解析(离线源)
- `DownloadSettings`(目录/并发/原图);`SaveButton`/`photoAccessHelper` 导出(避免宽存储权限)
- **`@ohos.request.agent` 能否携带 cookie + token spike**;不行则退 ContinuousTask
- 契约测试:`test_download_queue_contract.mjs`、`test_offline_read_contract.mjs`

## M5 — 评论、评分、设置纵深、反封锁、历史/Toplist

评论看/发/投票/翻译,画廊评分,完整设置中心(EH uconfig 同步、阅读/布局/安全),阅读历史 + Toplist,反封锁网络层。

- `entry/pages/CommentPage`(富文本 span,发/回/投票,机翻)+ `AddTagPage`;`EhGalleryCommentParser` + 评分(Rating → api.php rategallery)
- `feature/settings`:`SettingsPage` 中心 + 子页(`ReadSettings` 音量键/自动翻页/方向、`LayoutSettings`、`SecuritySettings`、`EhUconfigPage`、`CustomHostsPage`、`ProxyPage`、`BlockRulesPage`、`AboutPage`、`DiagnosticsLogPage`)
- `shared/network`:DoH + 自定义 hosts/IP 直连(`@ohos.net.rcp` 自定义 resolver 或预解析 IP)、per-host 令牌桶、509/429;`CustomHostsSettings` + `NetworkProxySettings`(用户代理/VPN)
- `feature/home`:历史 tab(`HistoryRepository`)+ Toplist tab(`tl=`);阅读器自动翻页/音量键/常亮收尾
- `BlockRulesSettings`(标题/上传者/评论者/评论正则过滤);`feature/user` uconfig 资料 + 限额;`AutoLockService`(生物认证 + 窗口隐私)
- 各落地子系统配套契约测试

## M6 — 同步、高级特性、打磨(延后长尾,P3)

WebDAV 同步、图片屏蔽(pHash+QR)、自定义 tab 组、搜图、种子、相似搜索、EPUB 导出。

- `shared/storage`:WebDAV(`@ohos.net.http` PROPFIND/PUT/GET)同步历史(墓碑)/读进度/快速搜索/分组(**MySQL 同步放弃——无 ohos 驱动**)
- `entry/ImageSearchPage`(picker + multipart `image_lookup.php` → Location → 列表)+ 相似搜索 + `EhTorrentParser`/种子对话框
- `PHashUtils` + QR 扫描(`@hms scanCore`)图片屏蔽;`feature/home` 自定义 tab 组
- EPUB 导出 + 标签投票;更新/关于打磨;平板双栏(`NavigationMode.Split`)
- 全量 i18n 审计、主题令牌 grep 契约、真机 QA 截图

---

## 顶层风险

1. ~~**域名前置**~~(已放弃):「连 CDN IP + 改 Host + 跳证书校验」在主流 CDN/SNI 层已被封死,不可用。改用 **DoH 解析真实 IP + fallback IP 直连(正常 SNI、不绕证书)+ 用户代理/VPN**,标准 `@ohos.net.http`/`rcp` 即可——这消解了原来最大的基建风险。仍需:DNS 被污染时走 DoH/预解析 IP;IP 也被封时依赖用户自备代理/VPN。传输层围绕**可插拔 resolver/proxy** 设计,但不阻塞 M1 表站浏览(常可直连)。
2. **阅读器无 ArkUI 等价的 ExtendedImage/PhotoView**:捏合/平移/双击缩放须手写矩阵变换 + 与 Swiper 翻页/点击区共存(eros_fe 用 3 套 Flutter 后端才搞定)。缓解:M2 专项 spike 先验证单页内手势-缩放+翻页共存;独立 HAR 隔离;只选一套方案(Swiper 横 + List 竖),不移植 3 后端;先竖滑后翻页。
3. **Dart→ArkTS parser/model 移植**是主导正确性风险:ArkTS 禁解构/展开/map 字面量/`obj['x']`/`any`,每个 ~50 字段 model 和每个正则/DOM parser 须逐字段手写。sprite 评分/favcat 魔法常量绑定 EH 实时 sprite。缓解:尽早抓真实 HTML fixture,每 parser 配契约测试,verify-live,重解析走 TaskPool。
4. **整图内存 + per-IP 一次性 token + 509 日配额**与 V2Next 文本缓存/nhentai 静态 CDN 都不同。缓解:流式落盘 + sampleSize 解码;从 M2 起在 `ImageResolveService` 建模 token 生命周期 + 509/429 分流。
5. **HDS 组件**(`@kit.UIDesignKit`)是壳的核心,SDK 26 内置可用(V2Next 已证)。缓解:M1 升级 HDS 壳前先小范围验证。
6. ~~**合规/分发**~~(已消解):本应用**不上架,仅 sideload**,无应用商店审核约束。里站(成人内容)、GitHub 标签库下载、域名前置、广存储权限等均可原样发布,无需灰度/隐藏开关。剩下的只是各自的**技术**可行性(网络可达见风险 #1),与合规无关。
7. **后台下载**:HarmonyOS 无默认长驻线程,`@ohos.request.agent` 能否携 cookie+token 待证(Flutter 端从未真后台下载)。缓解:M4 先 spike。

## 待确认决策(已采用推荐默认,可调整)

下列默认已落进脚手架/文档,如需调整请告知:

| 决策 | 采用默认 | 影响 |
|---|---|---|
| 包名/标识 | `com.erosteam.nexte`,vendor `erosTeam`,label NextE,v1.0.1,targetSdk 26.0.0 | 已写入 `AppScope/app.json5` |
| 签名 | **复用** V2Next 账号级调试证书,仅单独签发 `com.erosteam.nexte.p7b` profile | `scripts/dev.env.sample` |
| 模块拆分 | entry + shared + home/gallery/search/reader/download/user/settings(9 模块,reader 独立 HAR) | 已写入 `build-profile.json5` |
| MVP 范围 | eros_fe P0 集(M1–M3 达成表/里站浏览+详情+阅读+登录) | 路线图 |
| 里站(ExHentai) | **原样支持**(登录 + igneous 门禁),不灰度不隐藏 | M3;不上架无合规约束 |
| 分发渠道 | **仅 sideload(不上架)**,GitHub Release;**保留**应用内更新检查(无商店接管,sideload 需自更新,移植 eros_fe update_controller) | 已定 |
| 权限策略 | 不上架,可按需用宽权限;默认仍优先 `SaveButton`/`photoAccessHelper` 等最小授权(纯工程整洁,非合规) | M4 下载导出 |
| 反封锁传输 | DoH + fallback IP 直连 + 用户代理/VPN;**不做域名前置**(已废弃) | 已定 |
| 语言集 | base + zh_CN + en_US + ja_JP(EH 受众偏 zh+en+ja),严格 key 一致 | 已落地 |
| 同步 | 放弃 MySQL;WebDAV 延到 M6;但**现在**就给历史/读进度 RDB schema 加墓碑元数据 | M3 schema |
| 云同步 | 开发/私有构建启用 `cloudStructuredDataSyncEnabled` + DISTRIBUTED_DATASYNC;公共构建可用 `NEXTE_HUAWEI_CLOUD_SYNC=0` 关闭 | 进行中 |
| 深色主题 | v1 单一深色(不做纯黑/灰双变体),固定强调色(不做取色器),与 eros_fe 一致 | 减半资源维护 |
| 自定义 tab 组 | 延到 M6(v1 默认单画廊 tab 足够) | — |
