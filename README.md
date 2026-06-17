# NextE

原生 **HarmonyOS NEXT**(ArkTS/ArkUI)的 **E-Hentai / ExHentai** 客户端。

> 移植 Flutter 应用 [eros_fe](https://github.com/3003h/Eros-FE) 的功能与交互,采用成熟应用 V2Next 的工程架构与规范。包名 `com.erosteam.nexte`,SDK 26.0.0(API 26)。

## 状态

🟢 **M0 脚手架已完成并验证** —— 9 模块 Hvigor monorepo 构建通过(`hvigorw assembleHap` → BUILD SUCCESSFUL),状态管理 V2 零违规,模块/i18n 门禁绿。后续里程碑见 [docs/roadmap.md](docs/roadmap.md)。

## 工程结构

```
NextE/
├── AppScope/                 应用级配置与资源(app.json5, 图标, app_name)
├── entry/                    入口模块: 导航壳 + 跨 feature 页 + EntryAbility
├── shared/                   零依赖共享库
│   └── src/main/ets/{network,parser,model,state,settings,components,
│                     theme,services,utils,constants,cache,storage,
│                     diagnostics,i18n}
├── feature/                  feature HAR(各仅依赖 shared,互不导入)
│   ├── home/      多源画廊列表
│   ├── gallery/   画廊详情
│   ├── search/    搜索 + 高级筛选
│   ├── reader/    图片阅读器(独立 HAR)
│   ├── download/  下载队列 + 归档
│   ├── user/      收藏 + MyTags + 资料
│   └── settings/  设置中心
├── scripts/                  契约测试 + 签名脚本
│   ├── test_v1_decorator_inventory_contract.mjs
│   ├── test_version_consistency_contract.mjs
│   ├── check_i18n_duplicates.py
│   ├── build_hvigor_signed.sh
│   ├── sign.py  +  dev.env.sample
├── docs/                     架构 / EH 集成契约 / 路线图 / agent 指南
├── dev.sh                    Linux legacy helper; macOS 不使用
├── CLAUDE.md  AGENTS.md       开发规范与约束
└── build-profile.json5  oh-package.json5  ...
```

## 构建

需要 DevEco command-line tools(`hvigorw`/`ohpm` 在 PATH),`DEVECO_SDK_HOME` 已配置。

```bash
ohpm install                                                          # 解析依赖
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon   # 构建 unsigned HAP
```

当前 macOS 工作流使用官方 DevEco/Hvigor build-profile 签名路径:

```bash
bash scripts/setup-local-build-profile.sh   # 安装 ignored 的本地签名 build-profile.local.json5
bash scripts/build_hvigor_signed.sh         # 官方 Hvigor 签名构建,产出 entry-default-signed.hap
```

`dev.sh` 是 Linux legacy helper,不要在 macOS 上使用。

Linux legacy helper(签名需先准备物料,见下):

```bash
bash dev.sh --build-only     # 仅构建
bash dev.sh                  # 构建 + 签名 + 安装
bash dev.sh --help           # 帮助
```

签名:macOS 使用 ignored 的 `build-profile.local.json5` 和 `scripts/setup-local-build-profile.sh`。Linux legacy helper 使用 `scripts/dev.env`(从 `scripts/dev.env.sample` 复制,gitignored)填入签名物料路径/口令。复用账号级调试证书,需单独为 `com.erosteam.nexte` 签发一个调试 Provisioning Profile(`.p7b`)。

## 门禁

```bash
node scripts/test_v1_decorator_inventory_contract.mjs   # 状态管理 V2 强约束(须 0 file)
node scripts/test_version_consistency_contract.mjs      # 模块注册一致性
python3 scripts/check_i18n_duplicates.py                # 多语言 key 一致 + 去重
```

## 计划功能(对照 eros_fe)

- 多源列表(画廊/关注/热门/Toplist/收藏/历史)+ 列表/网格/瀑布流视图切换
- 画廊详情(标签/评分/缩略图/评论)、图片阅读器(翻页/竖滑/缩放/自动翻页/音量键翻页)
- Cookie 登录、表站/里站切换、搜索/高级搜索、标签翻译
- 远程 + 本地收藏、MyTags 管理、EH 设置同步
- 下载/原图/归档/离线阅读、评论发表与投票
- (长尾)WebDAV 同步、图片屏蔽、生物认证锁、搜图、EPUB

## 参考与致谢

- 功能/UI 参考:[eros_fe](https://github.com/3003h/Eros-FE)、[E-HentaiViewer](https://github.com/kayanouriko/E-HentaiViewer)、[EhViewer](https://github.com/seven332/EhViewer)
- 架构/规范参考:V2Next(HarmonyOS NEXT V2EX 客户端)
- 标签翻译数据:[EhTagTranslation/Database](https://github.com/EhTagTranslation/Database)

## 许可

[MIT](LICENSE)
