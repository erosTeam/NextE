# NextE 旧版与共享阅读器：行为、所有权与生命周期对照

日期：2026-09-26。状态：**不兼容结论已成立；完整等价尚未证明；持续本地阅读缺陷 OPEN。**

这份文件是源码对照和修复约束，不是验收证书。不得把表中“接线存在”“复用服务”“相同菜单项”改写为“行为一致”或“用户路径通过”。本次没有修改产品代码、增加测试、构建、安装或操作设备。

## 1. 结论与证据边界

当前迁移不只是替换图片渲染底层。菜单构建、自动阅读调度、页面资源窗口、原生图片生命周期、读取进度提交时机、宿主设置到运行时策略的同步均有独立实现。因此，不能证明所有行为没有改变；其中自动翻页计时及就绪条件、原图替换时保留画面的方式已经存在源码可确认的差异。

用户最新反例：归档下载画廊超过初始若干页后持续出现加载指示；普通下载画廊后续翻页也有黑帧。此前记录的打开和少量前后翻页不足以覆盖这两条路径。此前任何从这些片段推广出的“下载阅读没有问题”结论撤回。问题不转交给用户寻找或复现。

“初始窗口之后没有预载”目前不能作为已证实原因：源码确实移动窗口。相反，“窗口移动所以预载正常”也不能成立，因为文件可用、资源会话 ready、原生 Image 已解码、目标页面实际有像素是不同状态。

### 固定比较对象

| 对象 | 版本及含义 |
|---|---|
| 当前 NextE | `/Users/honjow/.codex/worktrees/eceb/NextE`，`f2ff3a86eb017e4f8bf2f7af24c82156dda9e2af`；本轮调查开始工作树干净 |
| 当前核心 | NextE `third_party/reader-kit` 与权威目录 `/Users/honjow/.codex/worktrees/c585/NextN/third_party/reader-kit`，`ccf472dcd2fd7899d584061b8b8fc31722481bd0` |
| 用户要求保留的基底 | `c94b43fa129ab6cf997dfc1b654ed94f82f3025c`，不是无缺陷证明 |
| 历史旧版源码对照 | `719a7c2643b059d7ee0707cff0e63b135244ccf9`；用于识别后续修改，不能冒充用户确认的绝对无缺陷版本 |
| 当前旧版 | 当前 `ReaderPage.ets`；它本身也被修改，不能只拿当前旧版与当前新版互相证明 |

历史对照到当前，`ReaderPage.ets` 差异为 133 行增加、366 行删除；包括加载 UI 抽取、关闭回调与快照身份、原图可用性及图片节点保留。归档与普通下载源服务在该区间没有差异。行数只用于固定审查范围，不是质量指标。

本文路径均相对 NextE 根目录；`kit/` 表示 `third_party/reader-kit/`。给出的行号固定于上述版本。

## 2. 所有权对照：迁移实际改变了什么

| 状态/职责 | 旧版所有者 | 共享版所有者 | 结论与约束 |
|---|---|---|---|
| 用户持久设置 | ReadModeSettings / ReadModeState | 仍为同一宿主服务 | 共享组件不能另设一份产品默认值代替它 |
| 当前布局/方向 | ReaderPage 直接消费 readMode，并管理单/双/List | 宿主 InitialPolicy 映射到 ReaderPagedSession.policy，Chrome 再经 PreferenceSink 回写 | 新增双向同步边界；曾漏掉反向监视，不能把“持久化成功”算即时生效 |
| 页码意图 | ReaderViewModel.currentIndex / native controllers | session anchor/displayIndex/navigationRevision | 不等于用户已经看到的页 |
| 已呈现页 | loadedPages、图片回调和当前 index | observedAnchor、presentedSnapshot、drawable receipt | 新增独立呈现状态；菜单、进度、退出目标必须明确取哪一个 |
| 页面资源 | 页组件 SourceRequest + 宿主缓存 | 每个窗口 slot 的 ReaderSession + Asset/plan | 离窗会关闭 session，重入会新建 slot；不能以外层节点稳定证明资源连续 |
| 图片节点 | 旧版各模式图片层 | ReaderPagedCell / ReaderPagedImage；连续模式也复用其绘制部分 | 节点身份与 slot、fragment 关联；异步结果必须属于同一个绘制对象 |
| 初始/替换加载 | 旧版局部 loaded/progress/failure 状态 | session phase + replacementLoading + cell retained/decoded identity | 不是仅换指示器样式，而是重写了触发和退场规则 |
| 缩略图转场 | 宿主 ReaderThumbnailTransitionCoordinator | 宿主 coordinator + kit entry geometry/presentation handoff | 两层协议；图片请求进度不能接管导航动画寿命 |
| 菜单构建 | ReaderPage builders | ReaderChrome builders + hostActions/settings ports | 确实存在菜单迁移；这不是底层替换的自然必需项 |
| 自动翻页 | ReaderPage interval + warmForAutoRead | ReaderAutoReadController + snapshot gates | 调度与就绪语义不同，详见第 6 节 |
| 缩略图栏 | ReaderPage List/scroller | ReaderThumbnailRail + 独立 ThumbnailWindow | 栏存在不等于滚动动画/节点寿命等价 |
| 生命周期退出 | ReaderPage + overlay navigation | LabPage、Surface、session、trial window、root close context | 必须逐层注销，不能通过清空整个树替代状态更新 |

### 资源与呈现链路

旧版本地：完整本地 seeds → 页级组件挂载/解析 → file URI → 原生 Image → complete → loadedPages / 当前页呈现。

共享版本地：完整本地 seeds → catalog.page → 窗口 ReaderSession → Asset(file URI) → phase=decoding → cached native viewport → ReaderPagedCell → ReaderPagedImage → native complete → post-frame receipt → session presentation → selected visible/observed position。

共享版多出的每个阶段都必须有明确的所有者和有效期。不能把某阶段的“完成”拿来替代后续阶段；也不能在仍显示旧画面时用新请求状态清空唯一图片节点。

## 3. 下载连续阅读：已证实与未证实

### 3.1 排除错误归因

- `shared/.../ReaderLocalSourceService.ets:30,54,88,154,181`：普通下载验证完整有序文件 seeds；归档先取得全部图片，再建立本地参数；在线入口可以优先切到已完成本地源。
- `shared/.../ArchiveImageService.ets:30`：已有解压目录则扫描，否则等待 `zlib.decompressFile` 完成后列出全部图片。该路径不是阅读器每翻一页流式解压一张。
- `feature/reader/.../NextEReaderLabAdapter.ets:168,221,335`：local page 标 bodySourceReady；local preload 直接返回；local load 返回 file URI 及 no-op release。这里没有逐页下载/解压。
- 旧版 VM 的网络 precache/warmPreview 同样跳过 local。旧版 `ReaderCacheWarmers` 的挂载点 `ReaderPage.ets:464` 排除了 local。**不能把缺少在线 warmer 当作本地问题原因。** 本轮早期曾作此猜测，已纠正。

### 3.2 窗口并非只计算一次

`kit/reader-core/.../ReaderPagedSession.ets:699` 按当前 displayIndex 或连续可见区加减 depth 计算窗口；`selectDisplay` 经 rebuild/reconcile 更新。`ReaderSurface.ets:396,438` 将 preloadDepth 送入资源预载及 paged window；snapshot 的 nativeCacheDepth 在 `ReaderPagedSession.ets:625` 下发给 `ReaderPagerSurface.ets:419` 的 cachedCount。

这只能证明“深度值和移动代码存在”，不能证明窗口新加入的 native child 在下一次快速翻页前已经取得正确尺寸、更新到最新 frame 并完成解码。

### 3.3 可以定位到代码的释放/重建边界

1. `ReaderPagedSession.ets:1202` 按窗口 sourceIndex 保留已有 slot；移出窗口的 slot 在 1217 调用 session.close。
2. 再进入窗口在 1221 创建新 ReaderSession，1223 分配新的 slotSerial。
3. `ReaderSession.ets:779` 关闭时释放 asset、清空 URI、请求身份、retained state。
4. `ReaderPagerSurface.ets:55` 按 nativeKey 保留外层 RenderItem；普通 snapshot 更新不发结构 reload。
5. 但 `ReaderPagedViewport.ets:490` 内层 ForEach key 是 slotId + fragment；新 slot 不能保留同一个图片单元身份。
6. `ReaderPagedSnapshot.forItem:197` 只从当前 window 提取 frames；不在 window 时返回空 frames。外层 native child 的存在不自动保证其图片子树存在。
7. 新 session 的 `load:527` 先清空 URI并进入 asset，再在 603 进入 decoding。`ReaderPagedViewport:964` 对 idle/asset/decoding 决定加载 UI。

这证明**资源窗口、原生缓存窗口、图片单元生命周期并非一个保证**。离窗重入路径会重新产生请求/组件身份；但它尚不能直接证明用户向前连续阅读的黑帧由哪一步触发。不得把这个风险写成已定位唯一根因，更不得按猜测加延迟、扩大 cachedCount 或隐藏 loader。

### 3.4 旧版的状态寿命不同

`ReaderPage:3021,3038` 用阅读会话内 loadedPages 记录已加载页；`6419` 将 initiallyLoaded 回灌图片层；`6645` 解析到 URI 后恢复该事实。共享版主要在窗口 slot/request/native drawable 维度保存完成事实。二者不是同一状态模型。

旧版这份 loaded 标志也不能被直接照搬为“该 native node 仍有像素”：新节点仍可能需解码。应继承的是旧版能连续阅读的所有权和准备过程，而不是复制一个 boolean 来消除指示器。

### 3.5 仍必须闭合的因果链

目前未证明：窗口前沿资源何时完成；cached native child 是否在非选中时得到非空、最新 frames；原生尺寸什么时候可用；active/geometry 条件是否延迟准备；用户快速翻到该页时哪一层先提交了空内容。这里保留 OPEN，不要求用户再找证据。本轮遵守源码审查优先，不进行设备实验。

## 4. 功能对照矩阵

判定：**复用**＝共用现有服务，但 UI 时序未由此证明；**映射**＝找到双方对应链路，仍需证明边界；**差异**＝源码能确认不同；**OPEN**＝不能宣称等价。

| 用户行为 | 旧版参照 | 共享版对应 | 判定/不能省略的边界 |
|---|---|---|---|
| 在线打开 | ReaderParams + VM.init | Adapter.open/page、独立页准备 VM | 映射；并发与取消不同，不能只比第一页 |
| 完成普通下载打开 | ReaderLocalSourceService | 同服务，localUnits | 复用数据；持续翻页已被用户否定，OPEN |
| 完成归档打开 | ArchiveImageService | 同服务解压后 file URI | 复用数据；持续翻页 OPEN |
| 在线入口命中本地 | preferLocal | Adapter.open 同服务 | 复用；录屏“在线入口”不证明无缓存在线 |
| 带缩略图进入 | Coordinator + 图片快照 | Coordinator + EntryTransition/native target | 映射；单页、双页左右落点、companion fade 分开 |
| 不带缩略图进入 | 系统导航 | root/live-source entry 分支 | OPEN；不能因有 thumbnail 专用协议而关闭系统动画 |
| 加载中操作 | chrome、turnTo、loading stage | session ready 与 asset phase 分离 | 映射；chrome/input 不得等大图下载 |
| LTR/RTL | ReaderModeMenu/setReaderMode | ReadingModeMenu/selectReadingMode | 当前四选项对应；此前被 RuntimeMenu 替代过 |
| 纵向分页 | TOP_TO_BOTTOM | single + vertical axis | 映射；不能连带改变 double 偏好 |
| 连续滚动 | VERTICAL/List | continuous/List | 映射；缓存与布局更新协议不同 |
| 单/双页切换 | doublePageEnabled及 spread mapping | setPolicy + IdentityMap | 映射；锚点、左右归属、剩余单页都属于行为 |
| 双页拼接/均分 | joined/split | spreadLayout | 映射；宽高补全后几何仍可能变化 |
| 双页错位 | gallery column mode | firstPageAlone/per-gallery persistence | 映射；不是全局设置替代单画廊选择 |
| 快速相邻翻页 | native Swiper | native Swiper + queued onSelect | OPEN；短路径通过不覆盖窗口前沿 |
| 缩略图栏跟随 | thumbScroller 动画 | ReaderThumbnailRail:45 按目标变化动画 | 映射；当前 key 以 index，宿主以 unit；并非每页必重建整栏 |
| 缩略图点击 | turnTo/index | seek intent + handoff | OPEN；所选位置与已呈现位置分开 |
| 滑条预览/提交 | slider/VM转页 | Chrome preview + ReaderPositionHandoff | 映射；取消、远跳、加载失败不能被跳过 |
| 普通翻页后页码 | currentIndex/publish | observed/presented projection | 差异：提交时机改变；加载等待时需逐项界定 |
| 原图单页开/关 | page original tokens、resolveOriginal | assetPlan/variant selectOriginal | 差异：共享版保留旧像素并双阶段替换 |
| 双页原图左/右/全部 | visualIndexes，all original 判定 | visualParts frames、all original 判定 | 映射；可用性、busy、stale-menu条件不同 |
| 原图失败/快速重复 | SourceRequest、resolving锁 | epoch/cancel、retained candidate/claim | OPEN；不能以一次成功开关覆盖全部 |
| 重新获取源 | requestSourceReload | forceReload解析 `/s/?nl=` | 映射；不能仅重新下载旧 CDN URI |
| 图片信息 | current/visual side info | ReaderImageInformation + host supplement | 映射；信息来源与显示variant需一致 |
| 保存左/右/全部 | ImageSaveUtil / source file | save controller + media port + saveUri | 映射；当前代码使用实际已加载文件；取消/部分成功独立 |
| 分享 | ShareUtil/system sheet | share controller/system presentation | 映射；只打开 chooser 不证明外发成功，也不应外发验收 |
| 裁边 | mode-scoped crop + image layer | CropPolicy + per-slot crop | 差异：entry期间延迟应用几何；不等于禁用检测 |
| 超分启停/模型/高度 | 原宿主服务与图片层 | SuperResolutionProvider/variant policy | 映射；模型相同不证明同一取消/回落时机 |
| 临时超分显示 | 宿主显示控制 | TemporaryVariantControl | OPEN；sheet、background、close状态需统一 |
| 翻译/显示原图/显示结果 | ReaderPage translation state | 宿主 provider + translated variant | 映射；原图与译图优先级不得互相覆盖 |
| 自动翻译 | 页面状态/调度 | currentSourceIndex + host actions/schedule | OPEN；观察页与意图页变化会影响目标 |
| 图片屏蔽/标记 | ImageBlock服务/图片层 | ImageBlockProvider/suppressed notice | 映射；终态不是持续 loading |
| 点按区域/反转 | 共用 Resolver | Host resolveTapZone/tapPolicy | 复用解析；事件识别仍是另一套 |
| 修改后的区域指示 | tapZonePreviewVisible | revision + Surface preview | 映射；第一下只关闭预览，不翻页 |
| 单击/双击冲突 | suppression/delay | TapSequence/zoom surface | OPEN；相同8px阈值不证明仲裁一致 |
| 缩放/拖动/复位 | 旧版各模式 zoom state | kit zoom state/native locks | OPEN；不得用禁翻页掩盖手势冲突 |
| 音量键 | ReaderVolumeKeys/consumer | input port + host foreground gates | 映射；退出与sheet必须释放控制权 |
| 自动翻页 | interval/next-ready | AutoReadController/displayed gating | 差异，详见第6节 |
| 设置打开 | 原 ReaderSettingsPage | hostSettings/bindSheet | 复用页面；active暂停/恢复另有协议 |
| 后台/前台 | route/window状态 | routeActive/labVisibility/active | OPEN；所有timer、request、输入持有者需同一边界 |
| 退出/系统返回 | closeReader/coordinator | closeTrial/ReaderCloseContext | 映射；native Back要使用真实当前画面，不是旧入口页 |
| 旋转/折叠 | native布局/旧图片层 | geometry identities/layout retention | OPEN；不能从普通翻页推导通过 |

## 5. 设置状态的完整字段责任表

来源：`shared/src/main/ets/state/ReadModeState.ets:75-103`，`NextEReaderLabPage:763,816-877,1151-1204`，`ReaderSurface:438-596`。本表是字段消费与寿命清点，不冒充逐项运行时证明。

| 字段/入口 | 当前共享版消费者与更新方式 | 约束/状态 |
|---|---|---|
| mode | Host @Monitor→InitialPolicy→session.setPolicy | 已有实时链路；保留独立double偏好 |
| doublePageEnabled | 同上；Chrome horizontalSpreadEnabled | 菜单与底栏必须从同一策略变化更新 |
| columnMode | 初始policy与单画廊progress映射 | 全局默认与单画廊错位不能混用 |
| spreadLayoutMode | Host @Monitor→setPolicy | 不应重开session |
| autoPageSeconds | AutoReadPolicy→controller | 秒数传播存在，调度语义不同 |
| preloadPages | Surface monitor→两种depth→nativeCacheDepth | 值传播存在，实际预解码效果 OPEN |
| volumeKeyTurn / volumeKeyTurnReady | 宿主 volume keys 及初始化资格 | 偏好与系统注册成功不是同一个值 |
| tapZoneLayoutPaged | tapPolicy/resolver + preview revision | 现有session内更新 |
| tapZoneLayoutContinuous | 同上，continuous分支 | 不覆盖paged偏好 |
| tapZoneInvertPaged | 同上 | 更新后预览和实际动作同源 |
| tapZoneInvertContinuous | 同上 | 同上 |
| backgroundMode | canvas/chrome颜色、status window | UI映射存在，不涉及重建reader |
| imageScalingQuality | imageInterpolation | 参数接线存在，不证明视觉差异已验证 |
| cropBordersPaged | current-mode CropPolicy | 与continuous分开 |
| cropBordersContinuous | 同上 | 非零裁边几何 OPEN |
| cropStrengthPaged | cropSourceRevision / provider | 重算检测，不以重建树应用 |
| cropStrengthContinuous | 同上 | 非零几何 OPEN |
| superResolutionEnabled | 配置/variantPreference | 资源身份与可用性要区分 |
| superResolutionModel | 配置identity/provider | 更换模型不能回写未授权默认值 |
| superResolutionBackend | 配置/provider | 后端不可用的降级行为仍需对照 |
| superResolutionMaxHeight | provider eligibility | 超阈值不是永久loading |
| showPageNumber | Surface参数 | 隐藏chrome时页码行为需保持 |
| fullscreen | Host窗口monitor | 打开sheet、返回与退出状态栏寿命另列 |
| readerImplementation | 下一次入口选择后端 | 不应重建当前正在阅读的实例 |
| keepScreenOn | Host keep-screen monitor | sheet/closing/foreground生命周期必须恢复 |
| pageTurnAnimation | Surface→native command | 动画关闭不等于更换组件树 |
| restoreResult / hadSuccessfulRestore | 设置恢复元状态 | 不是用户选项；不能算作已验收功能 |
| 模型管理导航 | SettingsSheet内容及modelsChanged | 不是开关；返回后刷新与失效模型处理需单独保留 |

### 标签与勾选

当前 `ReaderSettingsPage:834` 将一个 `readMode.readerImplementation` 传给 `SettingsChoiceRow`。`SettingsChoiceRow:22` 的行文字和 `:32` 的勾选都从这个 value 推导。此处结构已经避免分别提供 selected-label 与 checked-state；不能再建立第二份标签状态。它只证明当前实现的数据来源统一，不抹去此前截图矛盾。

设置打开卡顿相关源已有异步 `refreshSuperResolutionModels:159`；“async函数存在”也不证明内部计算全部离开UI线程。本轮不拿此前测试速度当作永久性能保证。

## 6. 明确不同，不能继续叫“等价”的部分

### 自动阅读

旧版 `ReaderPage:3081-3133` 用 setInterval；每次在非 jumping/zoomed 时检查下一页 preview 与 imageUrl/loaded，未就绪则 warmForAutoRead并暂停，之后重启。共享版 `ReaderAutoRead:77-105` 先要求当前display item所有part均为displayed，再检查下一item bodySourceReady；policy/topology/navigation/selection/slot/request/URI等进入identity，identity变化取消计时。

所以相同3秒设置不代表相同计时起点。当前页正在加载、双页一侧慢、元数据补全、原图替换及布局变更时可能不同。不能把更严格的条件当作未经授权的产品改善；应回到旧版行为决定是否必须恢复。

### 原图替换与加载提示

旧版明确切换source状态并显示重新加载过程；当前 ReaderPage 已改为保留native image挂载来避免空URI分支销毁。共享版 `ReaderSession:493-605` 将已显示旧asset保留，新asset经历decoding/claiming/displayed才释放旧资源；replacementLoading独立于phase。

“图片上有loader”需要区分用户主动替换（可以有旧图+进度）与普通已完成图片（不应残留）。不能用全局“有图就隐藏loader”修，也不能用全局“phase不是displayed就盖loader”掩盖native已完成却迟迟未提交状态的错误。

### 初始chrome参数

旧版 `ReaderPage:576,658` 消费 ReaderParams.initialChromeVisible；共享宿主 `NextEReaderLabPage:1201` 硬编码false。RouteParams注释说明true用于隐藏QA入口；目前搜索到的显式true写入在ohosTest。因此这是接口差异，**不能宣称普通用户默认入口已经因此出错**，也不能宣称参数完整保留。

### 加载UI复用的真实边界

旧版 `feature/reader/.../components/ReaderLoadingStage.ets` 与 kit `ReaderLoadingIndicator.ets` 中各自有加载展示实现。共享版给其他宿主提供 ReaderLoadingPresentation（文案、颜色、背景），不是要求各App重写shared loader；但它也不是直接调用旧版同一个组件。展示常数/样式相似不代表生命周期复用。真正要避免反复回归的是统一进度语义和原生画面所有权，而不只是统一外观。

## 7. 历史修改归因与不能声称的内容

- NextE `c94b43fa` 为保留基底；随后 `4f7bd4a2`、`0b9c12d6`、`3f2b15a7`、`e5625bd0`、`e35e1890`、`f2ff3a86` 分别涉及在线提示/双页落点、预览与实时设置、加载中chrome、返回context、原图/save以及布局/entry。这不是一份“只有底层实现修改”的历史。
- core `854c8be` 恢复方向控件、图片所有权；`ccf472d` 保留两种布局容器及稳定裁边entry。`ReaderLayoutRetention:18` 在unit变化才清空两种容器，模式交接保留outgoing直到incoming具备position/native条件。这解决的边界与持续窗口前沿不是同一个问题。
- 既有审计记录方向按钮曾绑定综合RuntimeMenu，并将来源指向早期提交；本轮已确认当前ReadingModeMenu与RuntimeMenu是不同构建器。**历史文件的归因不等于已经核验评审授权。** 没有可核实的评审批准证据，不能说“用户同意过改变菜单”，不能猜测某个人/会话的动机。
- 本次只能报告代码历史和具体变化，不能替缺失的设计评审补造理由。“共用组件需要统一菜单”不是改变既有按钮语义的授权。

## 8. 为什么既有问题会再出现：有证据的工程结论

1. 迁移以功能入口存在替代了行为合同：同名按钮背后变成另一状态机。自动阅读的不同等待条件是具体例子。
2. 稳定性证明停在外层：nativeKey不变，但内层slot key、空frames、URI挂载仍有独立变化；“没有重建Swiper”不能证明无黑帧。
3. 资源准备与画面完成混用：preload参数、磁盘文件可用被误当成native decoded/presented。最新本地反例正好落在此前未证明的窗口前沿。
4. 两份实现并行修改使参照漂移：当前旧版也有修改，只与当前旧版比较会漏掉对照组回归。
5. 局部路线被扩大为功能结论：首屏和几次相邻翻页不能代表持续阅读；录屏帧数、测试条数及额度消耗都不能弥补缺少的行为范围。

这些是源码和既有记录支持的范围；不是宣称已经找出本次黑帧唯一根因。

## 9. 对后续修改的实质约束

本节是继续实现的前置条件，不是另起一轮测试驱动开发。

- 以旧版实际调用链为参照，先写清被替换职责。已有宿主设置页、菜单产品语义、下载源服务、原图解析/缓存策略不因共享渲染而自动获得改写授权。
- 每个修改必须给出原有状态所有者、当前错误转移、最小恢复点。不能以截图相似、延迟若干毫秒、隐藏指示器作为因果依据。
- 普通导航不得更换同一source/variant的可复用drawable身份；移出窗口的释放必须与native缓存寿命一致。窗口深度配置不代替这项保证。
- 加载失败/重试、主动原图替换与邻页预备是不同事件。不能共用一个模糊loading布尔值控制所有节点是否存在。
- 导航、资源、呈现、chrome、持久设置可以有不同状态，但每一事实只允许一个权威写入者。派生状态必须标明来源，不能双向隐式回写形成新事实。
- 对已解决问题的防复活措施必须落在以上接口与所有权约束上；单独添加“回归案例通过”不改变架构，也不能关闭问题。
- 源码对照与恢复方案完成后，验证只用于检验既定实现，不反向发明行为。用户当前禁止测试驱动，继续有效。

## 10. 当前未关闭的工作

**不宣称已经完成全行为等价证明。** 本文给出了完整职责/功能范围的对照框架和已追到的关键链路；矩阵里的OPEN仍是实质工作，不是免责声明。尤其是本地持续翻页黑帧，尚需闭合窗口新加入页面到native准备的具体失效点；手势仲裁、全部增强/翻译失败分支、旋转/折叠、长期后台恢复也不能以参数接线代替深度等价证明。

下一步继续源码因果调查，先处理用户已经指出且本轮未定位闭合的本地持续阅读链路；在因果成立前不修改产品。不能把本文交付当作停止修复、让用户继续找问题的理由。

## 11. 复杂度与继续投入的判断

当前不能证明“复杂十几倍”，也不能拿文件行数替代复杂度。可确认的是接入宿主仍要协调自己的设置、路由、缩略图代理、前后台、翻译和增强偏好，同时与 kit 的 policy、asset request、native presentation、observed position、layout handoff 等状态互相通知。共享没有自动降低接入成本。

因此当前实现不满足“接入更简单、保留行为、便于扩展”的目标。是否保留某公共层必须按责任净减少判断，不能按已有投入判断：

| 部分 | 当前判断 | 取舍前必须满足 |
|---|---|---|
| 本地/在线源、文件缓存、业务解析 | 现有宿主服务已经复用，优先保留 | 不为kit再写第二套下载/解析规则 |
| 用户菜单及设置产品语义 | 应由既有产品合同约束，不应被通用菜单取代 | 按钮身份、内容、顺序、选中、作用范围一致 |
| 通用页映射和单/双/连续布局 | 有跨应用价值 | 不能以公共布局为由让宿主协调native图片生存期 |
| 图片请求取消与资源释放 | 有公共价值 | 一个请求所有者；离窗、替换、关闭各有明确转移，无重复版本状态掩盖错误 |
| 转场与呈现交接协议 | 复杂度集中且历史反复修复，不能默认全部保留 | 证明每层解决不同职责；仅为补偿拆分的层应合并或撤掉 |
| 三应用各自adapter | 只应适配资源与业务能力 | 不能要求三端照抄加载/解码/显示协调过程；当前NextE尚未达到这个门槛 |

后续方案不得默认“现有架构正确，只需补齐分支”。允许撤掉没有净收益的抽象、回用成熟实现；具体删除/替换必须先完成因果对照，不能再用一次重写制造新的行为漂移。当前不以NextN/Koma未来收益替NextE现有退化辩护，也不在它们上继续扩大接入。


## 12. 持续本地翻页的已定位断点与修复候选（2026-09-26 01:20）

第10节的“具体失效点尚未定位”已由以下证据推进，但全行为等价仍未完成。设备197的普通已完成下载走同一宿主/共享源码：资源窗口确实随页码推进；窗口新页的 ReaderPagedCell 已收到 URI，但缓存子树中的 ReaderPagedImage 没有同步挂载。source24/slot6 在 01:13:51.264 有资源，01:13:54.786 才挂载，恰在翻向它的手势过程中；后续新页重复约3.5秒延迟。初始窗口已有图片节点，因而开头几页表现不同。

修复只在共享 `ReaderPagerSurface.ets` 把系统 Swiper 的缓存改为 `cachedCount(nativeCacheDepth, true)`。官方 API15 契约说明第二个参数让缓存范围节点绘制并留在渲染树。使用既有节点和资源窗口，不增加宿主特殊分支、第二套图片缓存或翻页重建。前后诊断表明：新窗口页的资源到挂载延迟从约3.5秒降到4–6毫秒，解码提前到进入视口之前。具体 artifact、源码 patch、HAP 身份和仍待验证动作见 runtime audit 的 Active repair 段。

这不是通过隐藏加载器来掩盖未解码图片。真实未完成加载仍由既有状态负责；本轮不改变菜单、旧版行为、转场或设置默认值。连续帧及归档路由仍需完成核对，不能用本次日志推导整个阅读器无缺陷。


修复检查点：共享提交 `8dc64fb` 已同步到 NextE，临时诊断已撤除；最终 HAP `76b301e6…77033` 安装197后，从正常下载/归档入口各完成12次快速跨窗口翻页并返回。具体记录与观察范围见 runtime audit 的 Installed repair checkpoint。该检查点修复已定位的缓存绘制断点，不把全文其他 OPEN 项升级为等价通过。
