# NextE 视觉对抗审查 / 设计取向裁定档

> 用途:每轮视觉改动后,在这里留痕,**供用户事后核验**。
> 配套提示词见 [`docs/loop.md`](loop.md) §3(四源比对)、§5(记录)。
> 进度/假设在 [`docs/parity-driver.md`](parity-driver.md);此档只记**视觉对比与取向理由**。

每轮一条,新的加在最上面。模板:

```
## YYYY-MM-DD · <页面/组件名>

**对比截图**(尽量同画廊同项):
- eros_fe 真机:/tmp/xxx.jpeg   NextE 真机:/tmp/yyy.jpeg   并排:/tmp/cmp.png

**源码依据**(四源里的①②):
- eros_fe: <file:line> —— <结论>
- V2Next:  <file:line> —— <原生写法>
- NextE 改动: <file> —— <改了什么>

**设计取向 / 每处为什么这么定**:
- <项>:取值 <X>,依据 <源码位置/token>。
- ...

**有意保留的原生差异**(不是 bug):
- <项>:eros_fe 是 <Cupertino 做法>,我们用 <HDS 原生>,因此 <差异>。

**待修 / 存疑**:
- ...
```

---

<!-- 新的审查记录加在这一行下面 -->

## 2026-06-16 · 画廊列表卡片 GalleryCard(⑦ 视觉,不依赖 usertag②的部分)

**对比截图**(不同画廊,结构对比):
- eros_fe 真机:`/tmp/efe_c1.jpeg`   NextE 真机:`/tmp/nexte_card.jpeg`   并排:`/tmp/cmp2.png`(左 eros_fe / 右 NextE)

**源码依据(①②):**
- eros_fe `lib/pages/item/gallery_item.dart`:
  - `_CoverImage`(L212-378):封面宽 = `mediaQueryShortestSide / 3`(L233,**比例决策**);卡片样式只圆左侧两角 `BorderRadius.only(topLeft/bottomLeft = kCardRadius=12)`;封面在 `IntrinsicHeight` 的 Row 里撑满卡高。
  - `CoverImg`/`EhNetworkImage`(L609-671):`placeholder: CupertinoActivityIndicator()` + 灰底 `systemGrey5` —— 未加载时是转圈占位,不是透明。
  - `TagItem`(L529-565):**无 border**,`borderRadius 4`,`padding(4,2)`,`fontSize 12`,色 = `color ?? tagText(#505050)` / 底 = `backgroundColor ?? tagBackground(#eeeeee)`。
  - `_FavcatIcon`(L439-458):收藏心形在**评分行**(`[Rating Expanded][FavcatIcon][Filecont]`),`solidHeart size12`,色 = `favColor[favCat]`。
  - `_Rating`(L460-498):`StaticRatingBar size16`,**数字评分被注释掉**(只显星)。
- NextE 改动:`shared/.../components/GalleryCard.ets` 重排 + `EhThumbnail.ets` 加占位。

**这轮设计取向 / 每处为什么这么定:**
- 封面宽 = `px2vp(屏短边)/3`(`cardCoverWidth()`,V2Next 用 `display.getDefaultDisplaySync()`)——**照 eros_fe 的比例意图**,不是写死 116。
- 封面贴左/上/下、撑满卡高:`Flex(ItemAlign.Stretch)` + `EhThumbnail stretchHeight`(裸 Image 不设高,被父拉伸);卡片 `borderRadius RADIUS_MD(12) + clip(true)` 把封面左角圆成卡角、右角留方——对齐 eros_fe 只圆左两角的意图。
- 占位:`EhThumbnail` 灰底 `BG_SUB` + `.overlay()` 居中 `LoadingProgress`(仅未加载时,`@Local loaded` + `onComplete/onError` 翻转)——修"透明无占位"。
- 标签:纯灰平填充、**无描边**(源码证实 TagItem 无 border);per-tag 颜色只在 `SimpleTag.color/backgroundColor` 有值时取(usertag② 建好才有),**不按命名空间染色**。
- 收藏心形移到**评分行**(原生 `SymbolGlyph(heart_fill)` + favcat 色);评分只显星级、无数字(对齐源码)。
- **像素量(字号/圆角/padding)按原生 token 定**(标题 BODY、chip RADIUS_SM、padding 用 SPACE_*),不照抄 eros_fe 的 14.5/4/12——见 loop.md §2.3(b)。

**有意保留的原生差异:**
- eros_fe「汉语」蓝色 = 用户自定义 per-tag 色;NextE 现全灰,**正确**——usertag store(②)未建,无 per-tag 色源,默认中性灰。
- 页数:eros_fe 用 `Icons.panorama` 图标 + 数字;NextE 暂用 "{n}P" 文本(合法文本计数,非冒充图标)。
- chip 圆角/底色用原生 token,观感比 Cupertino 略不同但协调。

**待修 / 存疑:**
- per-tag hex 上色:等 usertag store(②)建好再接(driver.md 序列②)。
- 占位 spinner 仅靠代码+构建确认,未抓到加载中帧做视觉确认(封面加载快);后续可清缓存抓一帧。
- 收藏心形位置改了但本列表无已收藏项,未在真机看到;收藏页/已收藏项需再确认。

### 2026-06-16(续)· 对抗审查 workflow 复审(用户揪出评分星星)

**触发**:用户指出并排图里评分星星"来搞笑"+ 质疑我没真做对抗审查。属实——我上一版只核了"星星在不在"没核"渲染成什么样"。
**修(用户直接揪出,抠像素证实)**:评分 `Rating` 被 `.layoutWeight(1)` 撑成满宽 → 5 颗星均匀铺满整行(巨大空隙)。改 `.width(80)(=5×16)` + `Blank()` 推右 → 紧凑一簇,对齐 eros_fe `StaticRatingBar size16`。
**多智能体对抗审查 workflow `wbpe72wl2`**(6 维度 agent 各读两边真机图+源码找缺陷 + 综合,7 agent / 26 万 token)。结论与处理:
- 【中·已修】标签 chip 横向 padding 是 eros_fe 2 倍(`SPACE_SM(8)/SPACE_XS(4)` vs 源码 `TagItem (4,2)`)→ 短标签撑成两侧留灰边的宽药丸。改 `padding 6/3`(原生贴近 eros_fe 4/2 的 snug 值)。真机验:chip 贴字、灰边消失。
- 【低·已修】缺第二个 spacer(eros_fe 上传者后 + 标签后共两个 Spacer)→ 稀疏卡头重。补 uploader 后 `Blank()`,稀疏卡标签居中、meta 钉底。
- 【中·评估后跳过】foot 在 category+date 都空时塌陷:实际 date 由 `EhGalleryListParser` 必填、永不触发 → 非真实场景,记档不改。
- 【低·延后】封面无极端比例 Contain 回退(eros_fe 比例 >1 或 <3/5 时 `BoxFit.contain`+灰底,NextE 一律 `Cover` 硬裁):潜在、需把 `EhGallery.imgWidth/imgHeight` 接进 `EhThumbnail` 选 fit。本轮不扩范围,记 driver.md 待后续。
**复审后并排**:`/tmp/cmp3.png`(左 eros_fe / 右 NextE)——星级紧凑、chip 贴字、结构对齐。
**教训**:我一眼扫的"审查"无效;靠多智能体对抗审查(默认假设有缺陷)才抓出 chip padding 这种源码级偏差。视觉审查必须走 workflow,不能我自己走过场。
