# NextE 技术债与结构演进调研（2026-08）

> 状态：调研快照已完成；不是实施计划、规范或自动授权。  
> 基线：`0a9ddc8eb38a92ceefd996ce37cc06d867aea1b7`（`release: prepare v1.3.1`）。  
> 调研分支：`codex/tech-debt-audit-20260811`。  
> 调研 worktree：`/Users/honjow/git/NextE-wt/tech-debt-audit-20260811`。  
> 最近复核：2026-08-11。  
> 本轮边界：只调查、量化和提出后续路线；没有重构业务源码、改变 UI、修改数据结构或迁移持久化数据。

## 1. 结论先行

NextE 当前不是“架构失控”的项目。九个 Hvigor 模块仍保持正确的单向依赖：`entry` 负责编排，七个
feature 只依赖 `shared`，没有观察到 feature 之间互相 import，也没有观察到 `shared` 反向依赖
feature/entry。State Management V2、parser/network 分层、请求身份 fence、下载投影、Reader 请求 gate、
持久化 repository 和大量 Hypium/contract 资产，也说明项目已经建立了不少正确的工程接缝。

主要技术债不是“缺少分层”，而是**能力和变化集中在少数入口**：

1. `shared` 已经从基础共享层成长为占主 ArkTS 约六成的应用核心，并通过一个 1166 行、942 个导出
   specifier 的 barrel 暴露模型、组件、状态、设置、网络、存储、同步和大量业务服务。依赖方向正确，
   但公共面过宽、能力所有权不够清楚。
2. `ReaderPage`、`GalleryDetailPage` 和下载队列核心同时拥有多个互不相同的生命周期、远端动作、
   本地状态和 UI 呈现，是比“单纯行数大”更明确的耦合热点。
3. 原生 `reader_super_resolution_napi.cpp` 已经不只是超分 NAPI：它同时承载 NCNN/MindSpore 超分、漫画
   检测、气泡 mask、OCR、文字 mask、修复、全局模型缓存和 NAPI 异步桥接，文件名和实际职责已经失配。
4. 多处已经出现相同的可靠性模式，但还没有沉淀成小而明确的技术资产：可恢复串行写队列、
   “只保留最新值”的延迟写、同步 provider 调度、原子文件替换、缓存 prune 串行化、Grid/WaterFlow
   的列宽手势控制等。
5. 测试资产很多，但默认 GitHub Actions 只运行 CI preflight 和 production HAP build，不编译或运行
   `entry@ohosTest`。这会使大规模结构迁移依赖人工记住额外验证路径。

建议目标不是全局重写、微服务化、一次性拆成更多 HAR、引入 DI 容器或给每个类套接口。更适合的方向是：

- 保持当前模块化单体和 V2-only 状态管理；
- 先把重复且已经被多个真实场景证明的并发/文件能力沉淀为小型公共资产；
- 让高风险页面保留 UI 所有权，把独立的会话、动作和持久化生命周期迁移到粗粒度协作者；
- 让 `shared` 从“全量公共仓库”逐步变成有明确 capability 边界的应用核心；
- 先通过兼容 facade 和测试接缝迁移，再决定是否值得物理拆 HAR。

## 2. 调研口径与证据等级

### 2.1 纳入范围

- `entry/src/main/ets/`
- `feature/*/src/main/ets/`
- `shared/src/main/ets/`
- `shared/src/main/cpp/` 中的第一方代码
- `entry/src/ohosTest/ets/test/`
- `scripts/`、`.github/workflows/build.yml`、`scripts/run_ci_preflight.sh`
- 当前提交可见的 Git 变更历史

### 2.2 排除或单独统计

- `oh_modules/`、`build/`、`.hvigor/` 和本地构建产物；
- `shared/src/main/cpp/third_party/`；
- 自动生成的 `feature/settings/src/main/ets/generated/SystemSymbolCatalog.ets`；
- 图片、预编译库和二进制模型本身；
- 未在本轮运行的设备行为、性能和视觉结论。

### 2.3 证据等级

- **事实**：当前源码、配置、Git 历史或可重复命令直接得出。
- **结构推断**：由依赖、职责和变化集中度推断的维护风险，不代表已经发生用户可见缺陷。
- **建议**：后续实施候选，仍需按当时源码、用户范围和验证结果确认。
- **未知**：需要实现阶段构建、ohosTest、真机或性能 trace 才能确认。

本报告不把 LOC 当作缺陷。大文件只有在同时出现多职责、多个状态所有者、高变更频率、宽依赖或
难以隔离验证时才提高优先级。

## 3. 当前规模快照

### 3.1 仓库与主 ArkTS

| 指标 | 当前值 | 解释 |
|---|---:|---|
| Git tracked files | 1109 | 不含未跟踪构建产物 |
| 主 ArkTS 文件 | 459 | `entry + feature + shared` 的 `src/main/ets` |
| 主 ArkTS 行数（含一个生成目录） | 145675 | 用于模块规模对比 |
| 主 ArkTS 行数（排除生成目录） | 141625 | 后续大文件统计使用此口径 |
| `shared` ArkTS | 358 文件 / 88014 行 | 约占含生成主 ArkTS 的 60.4% |
| 非生成文件 `>=500` 行 | 68 | 只作为复核触发器 |
| 非生成文件 `>=1000` 行 | 30 | 只作为复核触发器 |
| 非生成文件 `>=2000` 行 | 5 | Reader/漫画/下载/详情/评论 |
| 非生成文件 `>=4000` 行 | 3 | Reader、漫画本地渲染、下载队列核心 |
| `entry@ohosTest` 测试源码 | 75 文件 / 18601 行 | 其中一个是集中注册的 `List.test.ets` |
| Git 提交数 | 1185 | 2026-06-16 至基线提交 2026-08-06 |

### 3.2 各模块主 ArkTS

| 模块 | 文件 | 行数 | 观察 |
|---|---:|---:|---|
| `entry` | 15 | 4150 | 主要集中在根导航 `Index.ets` |
| `feature/home` | 9 | 3725 | ViewModel 和列表 body 为主要热点 |
| `feature/gallery` | 18 | 12019 | 详情、评论、标签承担大量动作 |
| `feature/search` | 6 | 2436 | 页面公共面较宽，但业务实现相对小 |
| `feature/reader` | 9 | 9746 | 8367 行集中在一个页面文件 |
| `feature/download` | 4 | 2161 | UI 薄，核心行为大量位于 `shared/settings` |
| `feature/user` | 9 | 4893 | My Tags/Favorites 为热点 |
| `feature/settings` | 31 | 18531 | 含 4050 行自动生成符号目录 |
| `shared` | 358 | 88014 | 服务 40517 行，设置 13049 行，组件 8241 行 |

### 3.3 第一方大文件

| 文件 | 行数 | 触达提交 | 累计增删 | 初步分类 |
|---|---:|---:|---:|---|
| `feature/reader/.../ReaderPage.ets` | 8367 | 137 | 15005 | 多生命周期页面；高优先级 |
| `shared/.../ComicLocalVisualBackend.ets` | 6559 | 50 | 8595 | 大型单域算法管线；需拆阶段但不是简单 UI 巨类 |
| `shared/src/main/cpp/reader_super_resolution_napi.cpp` | 4261 | 26 | 4895 | 多原生能力 + NAPI glue；高优先级 |
| `scripts/comic_visual_regression.py` | 4122 | 9 | 4284 | QA CLI、解析、指标和报告混合；较低优先级 |
| `shared/.../DownloadQueueSettings.ets` | 4101 | 52 | 5569 | 队列、网络、文件、RDB、迁移混合；高优先级 |
| `feature/gallery/.../GalleryDetailPage.ets` | 3359 | 77 | 5869 | 详情读取、远端动作、下载、布局和弹层混合 |
| `feature/gallery/.../GalleryCommentsCard.ets` | 2152 | 43 | 4376 | reply 解析、翻译和交互呈现混合 |
| `feature/download/.../DownloadQueuePage.ets` | 1840 | 47 | 6230 | UI 投影已有抽取，但动作和展示仍集中 |
| `feature/user/.../MyTagsPage.ets` | 1747 | 22 | 2635 | 远端 tag/tagset 管理和页面状态集中 |
| `entry/.../Index.ets` | 1628 | 96 | 3270 | 合理的组合根，但 root action 和路由表可继续瘦身 |

“累计增删”来自 `git log --numstat`，反映历史变化量，不等于当前净行数或缺陷数量。

## 4. 已经成立的技术资产与正向约束

在提出拆分前，应保留以下已经有效的设计：

1. **模块依赖方向正确**：当前 feature 的 `oh-package.json5` 只依赖 `shared`；源码扫描没有发现
   feature-to-feature import。`entry` 是跨 feature 编排点。
2. **State Management V2 是可靠硬边界**：不能为了拆文件引入 V1 adapter、key churn 或临时桥。
3. **网络、parser、model 基本分开**：`EhHttpClient`、`EhApiService`、各 parser 和 model 已有明确职责，
   不应把它们重新揉回页面。
4. **已经出现好的可测试接缝**：
   - `ReaderSessionRequestGate`、`ReaderImageSourceRequestGate`；
   - `DownloadQueueTaskProjection`、`GallerySeedScheduler`、`GalleryResumeBatch`；
   - `IndexRouteCoordinator`；
   - 多个 account/site request fence；
   - `ImagePipelineService` 作为图片路径 facade。
5. **共享 UI 资产真实复用**：`ThemeConstants`、`AppStrings`、`DiagnosticLogger`、
   `GroupedListSection`、`SecondaryListScaffold`、`ConciseListRow`、PullRefresh 系列均有多个生产消费者。
6. **测试资产并非空白**：74 个实际 `*.test.ets` 由 `List.test.ets` 集中注册，另有 parser、持久化、
   secret、安全和 fixture contract。

后续治理应沿这些接缝扩展，而不是用一套新架构取代它们。

## 5. 核心发现

### F1. `shared` 的依赖方向正确，但公共能力边界过宽

#### 事实

- `shared/src/main/ets/Index.ets` 为 1166 行、337 条 export statement，共导出 942 个 specifier。
- 生产代码通过 `shared` barrel 导入了 506 个不同 symbol；ohosTest 导入了 316 个；两者合并使用
  724 个不同 symbol。仍有 218 个导出没有被当前生产/ohosTest 通过 barrel 使用。
- 101 个 entry/feature 主 ArkTS 文件中有 89 个 import `shared`。
- 生产 import 次数按来源分类，state symbol 为 600 次、component 331 次、model 195 次、service
  136 次、settings 110 次、network 39 次。
- `GalleryDetailPage` 一次从 `shared` 导入 105 个 symbol；`GallerySearchPage` 68 个；`Index` 64 个；
  `ReaderPage` 57 个。

#### 结构推断

当前不是典型的“每个 feature 拥有完整业务纵切”，而是“feature 主要承载页面，应用核心集中在
shared”。这个模式仍能工作，但随着 shared 增长，会出现三个问题：

- 修改者需要知道一个很宽的公共 API，能力归属难以从模块名判断；
- feature 页面容易直接同时使用 state、settings、network 和 service，绕过较窄的应用层入口；
- ohosTest 为测试实现细节而扩大 public barrel，使“可测试”与“应该公开”混为一体。

#### 建议

先做**逻辑 capability 边界**，暂不急于物理拆 HAR：

- `foundation`：theme、i18n、diagnostics、纯并发/文件工具；
- `eh-access`：HTTP、cookie、API、parser 和错误分类；
- `gallery-core`：画廊读取、评论/收藏/评分/tag 动作；
- `reader-core`：Reader 会话、图片、超分、翻译呈现；
- `download-core`：队列、存储布局、恢复、导出；
- `translation-core`：评论/漫画 provider-neutral 文档和 runtime；
- `persistence-sync`：RDB repository、backup、sync。

实施时保持根 barrel 兼容，先让新代码只经 capability facade 进入。只有某个 capability 的消费者、
构建成本和所有权都稳定后，再评估是否拆成独立 HAR。

#### 不建议

- 不立即把 `shared` 拆成十几个新模块；
- 不创建全局 `ServiceLocator` 或 DI 容器；
- 不为所有 class 机械增加 interface；
- 不用“最大 500 行”之类硬门禁代替职责判断。

### F2. `ReaderPage` 是最明显的页面职责集中点

#### 事实

- 8367 行；主 `ReaderPage` struct 本身约 4150 行。
- 主 struct 有 63 个 `@Local` 字段，源码模式扫描得到 262 个成员方法/Builder。
- 从 `shared` 导入 57 个 symbol，其中 service 17、state 17。
- 文件还包含 spread resolver、zoom coordinator、缓存 warmer、单/双页 surface、竖滑图片、加载与
  失败 overlay 等多个 file-local 类型。
- 137 个提交触达、累计增删 15005 行，是当前最高变更集中点。

#### 当前混合的生命周期

- route/session 身份与本地/在线 source 准备；
- status bar、keep-screen-on、volume key 和焦点；
- 单页、双页、RTL/LTR、竖滑、slider、tap zone 和缩放；
- 原图切换、文件缓存、预取、加载进度和重试；
- 超分前台暂停、应用、预取和状态显示；
- 漫画翻译自动策略、运行、缓存身份和展示切换；
- 图片屏蔽、分享、保存、菜单和多种 overlay。

这些并非一个 UI surface 必须同时直接拥有的同一生命周期。

#### 可行拆分顺序

1. **低风险纯逻辑/组件迁移**：把 `ReaderSpreadResolver` 和 file-local overlay/image 组件移入
   `feature/reader` 内部文件，保持参数与行为不变；补齐现有纯逻辑测试。
2. **独立运行会话**：把漫画翻译和超分各自的 page-index/cache-identity/async-epoch 状态迁移到
   `ReaderTranslationSession`、`ReaderEnhancementSession` 这类粗粒度对象。页面只订阅可展示状态和发命令。
3. **平台生命周期协作者**：把 status bar、keep-screen-on、volume key、focus 的成对注册/释放放入
   一个 Reader 平台生命周期协作者，确保一处拥有 cleanup。
4. **页面外壳收敛**：最后才把 route/session 初始化与 page/chrome presentation 收敛；不要先重写
   Swiper、手势或 UI 层级。

#### 验收重点

- 先复用 `ReaderSessionRequestGate`、`ReaderImageSourceRequestGate` 和现有 Reader tests；
- 每次只迁移一个生命周期，保持 `ReaderPage` 的对外参数和路由不变；
- ArkTS/V2 contract、signed build、`entry@ohosTest` 编译和相关 Hypium；
- 涉及手势、系统栏、翻页或翻译展示时，仍需要真实用户路径/设备证据。

#### 不建议

- 不把所有状态再搬到一个更大的 `ReaderViewModel`；
- 不引入通用“页面状态机框架”；
- 不在结构拆分中顺手改手势、预取数量、UI、文案或错误恢复语义。

### F3. `DownloadQueueSettings` 名称和职责已经失配

#### 事实

该文件 4101 行，并不只是 settings。它同时负责：

- gallery seed 调度、下载、取消、恢复和 resume-all；
- archiver 下载、断点/partial 文件、bot fallback 和错误分类；
- live queue state、进度 pulse 和信号发布；
- RDB 串行写、失败后的全量 reconcile；
- 元数据 sidecar 写入/读取、目录扫描导入；
- 公共 Download 目录授权、gallery/archiver 根目录和 `.nomedia`；
- UTF-8 字节安全文件名、旧目录/旧 Preferences 迁移；
- 恢复时 RDB 与磁盘元数据合并。

它被 52 个提交触达，最近的真实长文件名缺陷也落在这里。文件处于 `settings/`，但实际是下载领域
facade + engine + persistence coordinator + filesystem policy。

#### 建议的粗粒度边界

保留 `DownloadQueueSettings` 作为兼容 facade，内部逐步委托给最多四个主要协作者：

1. `DownloadFileLayout`：目录、文件名、partial/no-media、旧路径候选；
2. `DownloadQueuePersistence`：RDB 串行写、metadata sidecar、restore/reconcile/migration；
3. `GalleryDownloadEngine`：seed、并发、取消、恢复、速率限制；
4. `ArchiverDownloadEngine`：archiver 生命周期和错误/恢复策略。

进度发布可先留在 facade；只有两个 engine 都需要完全相同的发布语义后再抽公共 publisher。

#### 安全顺序

1. 先抽无 I/O 或可确定测试的文件名/路径 policy；
2. 用公共可恢复串行队列替换重复的 `rdbWriteTail.then(work, work)`；
3. 抽 persistence coordinator，保持双来源 restore 顺序和 reconcile 规则；
4. 最后迁移 gallery/archiver engine，所有消费者仍调用原 facade；
5. 稳定后再决定是否改名或移动 package。

任何一步都必须保留旧任务恢复、旧目录发现、RDB/metadata 一致性和取消语义；不能把“拆文件成功”
当作下载正确性证明。

### F4. `GalleryDetailPage` 是宽依赖的交互工作台

#### 事实

- 3359 行；主 struct 有 63 个 `@Local` 和约 182 个成员方法/Builder。
- 从 `shared` 导入 105 个 symbol，其中 state 51、model 18、component 11、network 3、service 5、
  settings 6。
- 页面同时承担详情读取、标题翻译、阅读入口、预览跳页、远端/本地收藏、评分、下载、archiver、
  tag、分享/复制、浏览器、弹层、平板 split 布局和 action follow-touch。
- 现有 `GalleryDetailViewModel` 已经较好地拥有读取、cache、请求身份和详情 read model，不应被进一步
  填成“所有动作的 God ViewModel”。

#### 建议

- 保留 `GalleryDetailViewModel` 的读取职责；
- 新增小型 `GalleryDetailActions` 或按真实生命周期分成：
  - favorite/rating/tag 的远端 mutation coordinator；
  - download/archiver action coordinator；
- 页面继续拥有 sheet/dialog/布局和视觉动画，只消费 command result 与稳定 read model；
- 标题翻译的 request/presentation state 可从页面迁移为独立 session，但动画参数仍留 UI；
- 不把所有动作抽成“一方法一个 use case”。只有涉及 await、状态所有权或多个消费者的动作才值得
  独立对象。

### F5. 评论预览与完整评论共享 UI，但 reply/翻译逻辑仍嵌在组件

`GalleryCommentsCard` 同时包含 inline image、reply id/mention 解析、候选评论匹配、blocked 展开、投票
呈现、structured translation、缓存命中和大量文本 layout。完整评论页又拥有一套翻译运行状态和动作。

优先候选不是再做一个巨型 Comment 组件，而是：

- `CommentReferenceResolver`：纯输入/输出，负责 reply id、mention 和引用快照；
- `CommentTranslationSession`：负责单评论的 cache/priority/in-flight/显示状态；
- preview card 与 full page 各自保留 UI 和分页所有权。

这样能让 reply/翻译规则成为技术资产，同时避免把两种页面强行统一成一个高参数组件。

### F6. 原生 NAPI translation unit 已包含多个独立产品能力

#### 事实

`reader_super_resolution_napi.cpp` 4261 行，CMake 只编译这一份源文件，但内部同时包含：

- NCNN Vulkan/CPU 和 MindSpore 超分；
- model prepare、tile、效果强度和 runtime cache；
- comic region detector；
- bubble mask；
- OCR recognizer + dictionary；
- text mask；
- inpainting；
- request cancellation、interaction pause、多个 mutex/cache；
- NAPI 参数解析、async work execute/complete 和 module export。

生产侧有六个 ArkTS wrapper 都 import 同一个 `libnexte_super_resolution.so`。保持一个 `.so` 是合理的，
但没有必要保持一个 translation unit。

#### 建议

保持 NAPI 导出名和 `.so` 不变，只做内部物理拆分：

- `napi/module.cpp`、`napi/value_reader.cpp`、`napi/async_tasks.cpp`；
- `runtime/request_control.cpp`、`runtime/model_cache.cpp`；
- `super_resolution/ncnn_upscaler.cpp`、`super_resolution/mindspore_upscaler.cpp`；
- `comic/detector.cpp`、`comic/recognizer.cpp`、`comic/masker.cpp`、`comic/inpainter.cpp`。

第一阶段只移动代码和收口 internal header，不改变模型、阈值、锁顺序或 NAPI contract。后续再判断
是否值得把不同模型 cache 变成显式 context。不要一边拆 translation unit 一边更换推理框架。

### F7. 已经出现可沉淀的“小型公共技术资产”

#### A. 可恢复串行异步队列

至少以下路径重复维护 `Promise<void>` tail，并用 `then(work, work)` 保证失败不阻塞下一项：

- SearchHistory、ViewedHistory、LocalBlock、GalleryReadProgress、LocalFav；
- DownloadQueue；
- CustomProfiles/LlmSource 的近似实现。

可抽一个只接受 `() => Promise<void>` 的 `RecoveringSerialQueue`。它无需泛型框架、优先级、取消或
重试；这些应由调用域继续拥有。

#### B. 只保留最新值的延迟写

`WebDavConfigPersistScheduler` 与 `SearchFilterPersistScheduler` 的实现几乎相同：timer + pending latest
write + serial tail + flush。可抽 `DebouncedLatestWriteQueue`，保留两个现有 class 作为薄语义 wrapper。

#### C. Provider 自动调度引擎

`WebDavSyncScheduler` 与 `HuaweiCloudSyncScheduler` 大量重复 debounce、最小间隔、指数退避、in-flight、
pending reason、suspend depth 和 timer 管理。可抽 provider-neutral engine，但 provider 的 enabled
检查、执行器和状态发布继续通过回调注入。该项风险高于 A/B，应在 A/B 成熟后实施。

#### D. 原子文件替换和目录工具

多个图片、模型、翻译和 cache 服务重复实现：ensure dir、`.part`/unique partial、rename、失败清理和
串行 prune。应只抽最小文件原语，例如 `ensureDirectory`、`replaceFromPartial` 和 `removeQuietly`；
不要做一个统一 Cache 基类，因为各 cache 的 key、限额、优先级和恢复语义不同。

#### E. Grid/WaterFlow 列宽手势策略

`PullRefreshGridScaffold` 与 `PullRefreshWaterFlowScaffold` 重复 pinch start width、一次跨列锁定、列数
计算、toast 和持久化。适合抽纯 `GalleryColumnResizeController`；两种 ArkUI 容器、spacer、cachedCount
和 near-end 逻辑继续分开。

### F8. 测试资产丰富，但自动验证拓扑不完整

#### 事实

- `entry@ohosTest` 下有 74 个实际 test 文件，由 `List.test.ets` 手写 import 并逐个调用。
- 测试源码约 18601 行；漫画/LLM 约 22 个文件，Reader 约 10 个，gallery/comment 约 9 个。
- `ComicLocalVisualBackend.test.ets` 本身 3876 行，含 45 个 test 和大量 fixture/helper。
- 当前 `.github/workflows/build.yml` 运行 `run_ci_preflight.sh`、安装依赖并构建 production HAP；没有
  `entry@ohosTest` build/run step。
- 当前仓库没有由 CI 执行的 ArkTS lint、复杂度或覆盖率配置；这不代表 DevEco 本地没有 IDE 检查。

#### 建议

1. 增加一个轻量 contract，校验每个 `*.test.ets` 都在 `List.test.ets` 被 import 和调用；
2. CI 至少编译 `entry@ohosTest`，设备执行可以保留为明确的手动/夜间 lane；
3. 把 3000+ 行 test 的 fixture builder/helper 拆到 test-support 文件，按 analyze/render/quality 分 suite；
4. 对结构重构记录“受影响的最小测试集 + 完整 suite”两级命令；
5. 不引入强制覆盖率百分比，不为 UI 源码形状新增正则 contract。

### F9. 迁移代码需要生命周期，而不是立即删除

`StorageKeys` 和多个 settings/repository 中保留了 Preferences→RDB、旧下载路径、旧凭据、旧同步格式
等迁移。这些代码有真实数据保护价值，但目前没有一个统一的“引入版本、最低支持版本、观察窗口、
删除条件”清单。

建议建立小型 migration inventory，记录：owner、旧格式、目标格式、首次迁移版本、是否幂等、失败时
保留源数据的规则和可删除条件。不能因为代码写着 legacy 就删除；只有产品支持窗口和真实升级证据
允许时才退休。

### F10. 部分大文件是合理集中点，不应机械拆分

- `SystemSymbolCatalog.ets` 是生成文件，直接排除。
- `shared/Index.ets` 主要是 barrel；问题是 API 宽度，不是要把 export 随机切成多个文件。
- `SettingsBootstrap` 是 composition root，集中 import 是职责的一部分。可把 page-cache warmup 移出，
  但不需要反射式注册框架。
- `ComicLocalVisualBackend` 是单一漫画视觉算法域，复杂度高但内聚性高于 Reader/Download。应按分析、
  source treatment、layout、render plan、drawing 阶段拆内部文件，不应抽成通用“图像处理框架”。
- Grid、List、WaterFlow 是不同 ArkUI 容器；共享 policy，不强行共享一个巨型 scaffold。

## 6. 优先级与收益/风险

这里的优先级是后续技术债 lane 的建议，不是当前授权。

| 候选 | 收益 | 实施风险 | 建议优先级 | 前置 |
|---|---|---|---|---|
| 模块方向 contract + public API inventory | 高 | 低 | A0 | 无 |
| `RecoveringSerialQueue` | 中高 | 低 | A0 | 现有 scheduler tests |
| `DebouncedLatestWriteQueue` | 中 | 低 | A0 | Search/WebDAV scheduler tests |
| 下载文件名/路径 policy 抽取 | 高 | 低中 | A1 | 现有长文件名与 RDB contracts |
| `DownloadQueueSettings` facade 化 | 很高 | 中高 | A1 | 先完成公共队列与路径 seam |
| Reader 纯逻辑/子组件迁移 | 高 | 中 | A1 | Reader tests + 行为基线 |
| Reader translation/enhancement session | 很高 | 高 | A2 | 一次只迁移一个生命周期 |
| Gallery detail mutation/download coordinator | 高 | 中 | A2 | 保持现有 read ViewModel |
| Comment reference/translation session | 中高 | 中 | A2 | preview/full page fixture |
| NAPI translation unit 拆分 | 很高 | 高 | A2 | signed build + native integration suite |
| Sync provider scheduler engine | 中高 | 中 | B1 | 先验证 A0 并发资产 |
| 原子文件小工具 | 中 | 中 | B1 | 明确各调用方 partial 语义 |
| 漫画 backend/test/QA script 分包 | 中 | 中 | B2 | 保持报告格式与阈值 |
| 物理拆分 `shared` HAR | 不确定到高 | 很高 | C / 延后评估 | 逻辑 capability 先稳定 |

## 7. 推荐的分阶段路线

### 阶段 0：建立可重复边界（1～2 个窄 PR）

- 固化当前 LOC/import/public API snapshot 命令，但作为报告，不设硬 LOC fail；
- 增加 module import direction contract；
- 增加 ohosTest registry contract；
- 明确 production build、ohosTest compile、设备完整 suite 的分层验收。

完成标准：不改变业务运行时行为；所有现有门禁通过；contract 只保护稳定严重边界。

### 阶段 1：沉淀低风险技术资产（2～4 个窄 PR）

- `RecoveringSerialQueue`；
- `DebouncedLatestWriteQueue`；
- 下载文件名/路径 pure policy；
- Grid/WaterFlow 列宽 gesture policy（可独立延后）。

完成标准：现有语义 wrapper 保留；逐个消费者迁移；每个 PR 可独立回滚；测试证明失败后续写、flush、
latest-wins 和 UTF-8 字节边界。

### 阶段 2：下载领域收口

- 保留 `DownloadQueueSettings` 公共 facade；
- 先迁 persistence/file layout，再迁 gallery/archiver engine；
- `DownloadQueuePage` 继续只消费 projection 和 commands。

完成标准：冷启动恢复、旧任务、暂停/恢复、gallery/archiver、partial、导入、删除、导出和长文件名矩阵
全部通过；RDB/metadata 双来源不丢数据。

### 阶段 3：Reader 与 Gallery 页面减负

- Reader 按纯逻辑 → translation/enhancement session → 平台 lifecycle 的顺序；
- Gallery detail 按 remote mutations/download actions 抽 coordinator；
- comments 抽纯 reference resolver 和 translation session。

完成标准：页面仍是 UI owner；route/参数不变；用户可见或交互行为需要对应设备证据；结构迁移不夹带
视觉或产品语义调整。

### 阶段 4：原生与漫画 QA 内部模块化

- 单 `.so` 多 C++ translation unit；
- 漫画本地 backend 按 pipeline stage 内部分包；
- QA Python 保留一个 CLI，将 manifest、recording、metrics、report/review 分模块；
- 超大 test 将 fixture builder 和 suite 分离。

完成标准：NAPI contract、模型输出身份、阈值、报告 JSON/HTML schema 不变；signed app、ohosTest 和完整
相关设备 suite 通过。

### 阶段 5：重新评估是否拆 HAR

只有满足以下至少两项才建议物理拆 capability module：

- 有两个以上稳定生产消费者；
- public facade 已连续多个改动保持稳定；
- 能显著降低构建、owner 或依赖冲突；
- 不会制造 feature-to-feature 依赖；
- 验证和回滚路径清楚。

否则继续在一个 `shared` HAR 内维持明确目录和 facade，成本更低。

## 8. 后续实施的硬边界

1. 保持 V2-only；任何 ArkTS/UI/state 变更都运行 V1 inventory。
2. 保持 `shared` 不依赖 feature/entry，feature 之间不互相 import。
3. 结构重构不改变 UI、交互、文案、网络协议、远端写入和数据所有权。
4. 通过兼容 facade 迁移，不进行大爆炸式 rename/move。
5. 每个阶段先写旧行为测试或复用现有 fixture，再移动所有权。
6. 不因“大文件”本身新增 CI 行数门禁。
7. 不把所有重复都抽象：只有至少两个真实消费者、相同失败语义和稳定输入输出的能力才沉淀资产。
8. legacy/migration 删除必须有版本与真实升级证据。
9. build/contract 只证明实现候选；手势、系统栏、下载恢复、设备性能和视觉结果仍需匹配的运行时证据。

## 9. 建议的 PR 拆分单位

一个可接受的结构 PR 应满足：

- 只迁移一个状态所有者或一个技术资产；
- 对外 API 保持，或提供兼容 wrapper；
- diff 中不混入 UI/产品功能；
- 有 before/after dependency 或职责说明；
- 明确最小测试集、完整 test target、signed build 和需要的设备路径；
- 可以通过 revert 单独回滚，不要求同时回滚后续五个 PR。

反例：一次 PR 同时拆 Reader、移动 shared module、改手势、换网络 client 并删除 migration。这种变化无法
可靠定位回归，也不符合本报告路线。

## 10. 可重复统计命令

以下命令都在基线 worktree 根目录运行。它们用于复核趋势，不建议全部变成硬门禁。

```bash
# 当前 worktree 和基线
git status --short --branch
git rev-parse HEAD
git worktree list --porcelain

# 主 ArkTS 文件与行数（排除生成目录）
git ls-files \
  | rg '^(entry/src/main/ets|shared/src/main/ets|feature/[^/]+/src/main/ets)/.*\.ets$' \
  | rg -v '/generated/' \
  | xargs wc -l

# 第一方大文件（排除 third_party/generated）
git ls-files \
  | rg '\.(ets|ts|js|mjs|py|sh|cpp|c|h|hpp)$' \
  | rg -v '(^|/)(oh_modules|build|\.hvigor|third_party|generated)/' \
  | xargs wc -l \
  | sort -nr \
  | head -n 120

# 文件触达次数
git log --format= --name-only -- '*.ets' \
  | rg '^(entry/src/main/ets|shared/src/main/ets|feature/[^/]+/src/main/ets)/' \
  | sort \
  | uniq -c \
  | sort -nr

# 依赖方向异常（正常应无输出）
rg -n "from '(home|gallery|search|reader|download|user|settings)'" feature shared

# 当前默认 CI 真值
sed -n '1,260p' scripts/run_ci_preflight.sh
sed -n '1,260p' .github/workflows/build.yml
```

## 11. 调研完成判定与仍需验证项

### 11.1 本轮文档与仓库基线验证

- `bash scripts/run_ci_preflight.sh`：通过；9 modules、四语言 key、severe boundaries 均通过；
- V1 inventory：`0 file(s)`；
- `git diff --check`：通过；
- 变更文档的相对链接检查：通过；
- 没有运行 signed HAP build、`entry@ohosTest` build/device suite 或真机路径，因为本轮没有改动业务、
  ArkTS、原生代码或运行时配置；因此本报告不把这些路径声明为当前已验证。

### 11.2 完成范围与未知项

本报告已经完成：

- 当前 worktree/commit 的隔离；
- 模块、目录、文件、公共 API 和 test topology 量化；
- Reader、Gallery、Download、NAPI、sync、file/cache 和 QA tooling 的源码抽样；
- Git churn 校准；
- 保守的分阶段路线、回滚边界和非目标。

本报告没有、也不能证明：

- 某次未来拆分一定提升运行时性能；
- 当前所有 ohosTest 在本机/设备仍通过；
- 物理拆 HAR 一定改善构建时间；
- 某个大文件已经造成具体用户缺陷；
- 用户可见行为可以在结构迁移中免验收。

这些结论必须在后续被明确授权的实施会话中，根据当时源码和对应验证补齐。
