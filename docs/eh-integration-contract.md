# EH 集成契约

NextE 通过 **Cookie 鉴权 + HTML/JSON 抓取**对接 E-Hentai / ExHentai(无 OAuth)。本文是 `shared/network` + `shared/parser` 的实现契约,逆向自 eros_fe(`network/request.dart`、`api.dart`、`parser/*`、`const.dart`)。**标注 "verify-live" 的常量绑定 EH 实时页面结构,移植后必须用真实 fixture 验证再依赖。**

## 域名与站点切换(`shared/constants/EhConstants.ets`)

- `EH_BASE_URL = https://e-hentai.org`(表站)、`EX_BASE_URL = https://exhentai.org`(里站);登录走 `forums.e-hentai.org`;JSON API 在 `<base>/api.php`。
- 缩略图 host 随站点不同:表站 `https://ehgt.org`,里站 `https://s.exhentai.org`。两套都要保留。
- 一个响应式布尔驱动一切:`connectSiteMode().isEx`(由 `SiteModeSettings.apply` 写入镜像)→ `EhConstants.baseUrl(isEx)` / `thumbHost(isEx)`,1:1 移植自 eros_fe `Api.getBaseUrl({isSiteEx})`。每站独立超时(表 10s/20s、里 15s/25s)。
- **里站门禁**:需登录 + `igneous` cookie(一次已登录的 `GET exhentai.org/uconfig.php` 返回 `Set-Cookie: igneous`);否则返回 "Sad Panda"。`EhErrorType.sadPanda` 启发式检测(panda 图的 content-type/size,或缺画廊标记的 HTML)→ 引导去登录/设 cookie。

## 端点(约 6 种形态,优先攻克 gdata + showpage)

| 页型 | 方法 / 路径 | parser → model |
|---|---|---|
| 画廊列表 / 搜索 | `GET /`(或 `/watched`、`/favorites.php`、`/popular`、`/toplist.php`),带 `f_cats`、`f_search`、`page`、游标 `next/prev/jump/seek/from`、`advsearch=1`+`f_*`、`favcat`;重试 `inline_set=dm_l`(扩展模式)、`fs_f/fs_p`(收藏排序) | `EhGalleryListParser` → `GalleryList{gallerys[], nextGid, prevGid, maxPage}` |
| 画廊详情 | `GET /g/{gid}/{token}`(HTML);抓内联 `var apiuid=(\d+);` / `var apikey="([0-9a-f]+)";` | `EhGalleryDetailParser` + `EhGalleryCommentParser` + `EhGalleryTagsParser` + `EhGalleryImageParser` → `EhGallery` |
| 图片页 | `GET /s/{imgkey}/{gid}-{page}`(HTML,`paraImage`)**或**快路径 `POST /api.php method=showpage`(需 `showKey`);509/坏图时 `nl=<sourceId>` 换源 | → `EhGalleryImage` |
| **`/api.php`**(单 JSON POST,按 `method` 复用) | `gdata`(批量 25 个 `[gid,token]` → `gmetadata[]`)、`showpage`、`rategallery`、`votecomment`、`taggallery`、`tagsuggest`、`setusertag`、`imagedispatch`(MPV) | `EhApiJsonParser` |
| 操作 | `/gallerypopups.php?act=addfav`(POST favcat/update/favnote)、`POST /g/{gid}/{token}`(评论)、`/mytags`、`/gallerytorrents.php`、`/uconfig.php`、归档 POST、`upld.<host>/image_lookup.php`(multipart 搜图 → 跟随 Location) | 各卫星 parser |
| 鉴权/门禁 | `POST forums.e-hentai.org/index.php?act=Login&CODE=01`(表单 UserName/PassWord/CookieDate=365);`GET exhentai.org/uconfig.php`(igneous);`GET home.php`(图片限额) | `EhUserProfileParser`,cookie 抓取 |

## Cookie / 鉴权模型(`EhCookieStore` + `EhCookieInterceptor`)

- `isLogin = ipb_member_id && ipb_pass_hash`(两者非空)。里站另需 `igneous`(+ `sk`)。
- 拦截器 `onRequest`:**始终**强制 `nw=1`;已登录则注入 `ipb_member_id/ipb_pass_hash/igneous/hath_perks/sk/star/yay/iq`。`onResponse`:把 `Set-Cookie` 收回 `EhUser`(`igneous=='mystery'` 或 `''` 视为未设)。
- **HarmonyOS 无内置 CookieJar**:手写 cookie store,经 `CookieJarSettings`/Preferences 持久化;`pass_hash` 敏感,严禁入日志(`DiagnosticsRedactor`)。EH cookie **长效**(不像 nhentai 轮换),WebView 登录后同步一次即可,**无需刷新循环**。
- `apiuid`/`apikey` 从详情 HTML 抓取,是每个 `/api.php` 写操作(评分/投票/标签)的必需参数;`gid`/`token` 来自列表/详情 URL;`showKey` 从首个 `/s/` 页抓一次,后续整本经 `method=showpage` 复用(快路径)。
- 写操作(评论、标签、搜图)以 HTTP **302/303 重定向**表示成功:**关闭自动跟随重定向**,读 `Location`(`getTextResponseWithHeaders`)。
- 远端写操作(评论、评分、投票、收藏、标签、归档、uconfig、消耗 GP 的图片配额重置)只能单次发送；即使服务端将动作暴露为 GET，也不得按读取请求重试。网络超时或 5xx 后结果可能未知，禁止由通用传输层自动重发；仅已确认只读的 `showpage`、`gdata`、`tagsuggest` JSON POST 可以重试。

## parser 清单(每页型 → model)

`EhGalleryListParser`→`GalleryList`;`EhGalleryDetailParser`→`EhGallery`(header);`EhGalleryCommentParser`→`EhComment[]`;`EhGalleryTagsParser`→`TagGroup[]`;`EhGalleryImageParser`→`EhGalleryImage[]`(**3 种缩略图布局**:`#gdt>div.gdtm` sprite / `#gdt>div.gdtl` / `#gdt>a`,全支持);`EhImagePageParser`(paraImage + paraShowPageJson);`EhApiJsonParser`(gmetadata/showpage/imagedispatch);`EhUconfigParser`→`EhSettings`;`EhMyTagsParser`;`EhFavoritesParser`;`EhArchiverParser`;`EhTorrentParser`;`EhUserProfileParser`;`EhAdvanceSearchParser`(URL query 解码)。

**必须原样照抄并 verify-live 的魔法常量**:评分 `(80-x)/16 - (y==21?0.5:0)`;详情 favcat `(pos-2)/19`;列表 favcat 按边框色对照 `favCat` 映射。重解析走 TaskPool worker(只传可序列化数据)。

## 图片分发与 reader 预取(`ImageResolveService`)

- `resolve(ser) → imageUrl`:已知 `showKey` → `POST /api.php method=showpage`(便宜);否则 `GET /s/` HTML 抓一次 `showKey`。MPV 备用管线(`/mpv/{gid}/{token}` → imagelist JSON + `method=imagedispatch`)v1 可选。
- reader 每次翻页预取后 N 页 ser → `ImageDiskCache` 预热,并发受限队列。
- **整图多 MB**:经 `@ohos.net.http` 流式落盘(**绝不** webview/base64),`@ohos.multimedia.image` 按 `sampleSize/desiredSize` 解码限内存。每整图 URL 带一次性 per-IP token,509 时跟随 `nl=` 重取。**509(图片配额)与 429(限流)分别处理**。

## 里站门禁与反封锁(尽早验证)

- 里站是 **Cookie 门禁**(`ipb_*`+`igneous`),**非** Cloudflare JS 挑战。原生 `@ohos.net.http`/rcp + 正确 Chrome UA + 同步 cookie store 即基线——隐藏 `Web()` 代理(eros_n_ohos 常开模型)对 EH 是过度设计/耗电。仅**登录**用可见 `@ohos.web.webview`(cookie → `WebCookieManager` → 镜像进原生 store)。
- **网络可达(不做域名前置)**:eros_fe 那套「连 CDN IP + 改 Host + 跳证书」在 CDN/SNI 层已被封死,**放弃**。NextE 用:① **DoH**(cloudflare-dns.com)解析真实 IP,绕 DNS 污染;② **fallback IP 直连**(正常 SNI,不绕证书);③ DNS+IP 都被封时依赖**用户自备代理/VPN**(`NetworkProxySettings`)。加 per-host 令牌桶(ehgt 20/400ms、e-hentai 5/800ms)防限流。标准 `@ohos.net.http`/`rcp` 即可,无需裸 TLS socket;表站匿名常可直连。传输层围绕**可插拔 resolver/proxy** 设计。

## 深链(entry `module.json5` skills → `EhUrlRouter` → `pushPathByName`)

为 `e-hentai.org`/`exhentai.org` 的 `pathStartWith:/g/` 与 `/s/` 注册 `viewData` skills(已在 `entry/src/main/module.json5` 配置)。`EntryAbility.captureIncomingUrl` → `publishPendingEhUrl(\`${Date.now()}:${uri}\`)` → `Index` `@Monitor` → `EhRouteNavigator.openInApp(ns, url)` → `EhUrlRouter` 解析 `/g/{gid}/{token}` → `pushPathByName('GalleryDetail', {gid, token})`。同一 navigator 复用于深链、内容内标签/画廊链接、以及恢复前台时的剪贴板链接检测。
