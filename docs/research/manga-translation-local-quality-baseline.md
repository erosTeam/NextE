# 漫画翻译端侧质量基线

- **status**: active baseline; not a production-quality claim
- **measured fixture profile**: `core-vision-ocr-directional-render-v13`
- **current production analyzer**: `core-vision-ocr-bubble-group-v21`
- **current production render profile**: `reader-local-bubble-layout-v37` /
  `local-ctd-aot-inpaint-v24` / `local-bubble-typography-v32`
- **measured**: 2026-07-21
- **device**: user-selected device `237`
- **fixture**: `nexte-original-manga-eval-v1`, two original 1024 × 1536 PNG pages

## 结论

当前端侧路径的速度已经达到即时阅读可接受范围，但检测覆盖和制图质量还没有达到通用 Reader V1 的退出
条件。两页小样的严格原文块命中为 **9/11（81.8%）**；成功检测的 9 个普通文本块方向为 **9/9**，阅读
顺序错误为 0。漏掉的两个块都是融入画面的拟声词。这个结果只能说明当前原创小样上的确定性基线，不能
外推成真实漫画总体准确率。

当前输出已经修复早期基线的几个明显问题：竖长气泡保持纵排和右到左分列；同一气泡被系统 OCR 拆开的
相邻列会重新合并；注音区域会随主文字进入清理范围。竖排禁则避免句号等闭合标点被单独挤到下一列。
原文处理不再绘制统一圆角块，而是检测文字区域内的高对比字形像素、膨胀 mask，并用局部邻域恢复背景。
v13 还以页面内纵排拟合字号的低中位数约束异常大字，第二页两个对白气泡不再出现约 42/30 px 的明显断层。

但这仍不是生成式内容感知修复：复杂纹理、描边艺术字和源字体风格没有专用模型，拟声词漏检时仍会保留
原文。因此本基线的产品判定是 **可用于轻量阅读试验，但不可宣称通用制图可用**；Reader 会给本地系统
OCR 结果附加待复核信号。与固定 Docker sidecar 的同页对照见
[视觉后端与可替换技术栈](manga-translation-backend-comparison.md)。

## 可复现测量

测试入口为 `entry/src/ohosTest/ets/test/ComicLocalVisualBackend.test.ets`。每次运行都会对两页执行真实 Core
Vision OCR、本地分组、确定性中文回填、PNG 编码、逐像素差异统计和进程 PSS 采样，并把 JSON 报告写入
测试 Ability cache。测试门要求至少命中 9/11、unexpected=0、所有已复核普通文本方向正确、改动画素低于
5%；这只是回归下限，不是 V1 质量门。

最终 v13 profile 在设备 `237` 连续三次目标质量用例均为 1/1。它是在完整 signed app 与显式 signed
`entry@ohosTest` 构建后运行；完整 Hypium 曾被既有 sidecar 长用例在本地 test runner 生命周期中提前
终止，因此这里不再沿用旧 profile 的“233/233”或“三次完整回归”表述。下表是第一轮保存的逐页报告：

| 指标 | 第 1 页 | 第 2 页 | 解释 |
|---|---:|---:|---|
| 严格原文块命中 | 4/5 | 5/6 | 每页均漏 1 个拟声词 |
| 已检测块方向 | 4/4 | 5/5 | 纵排/横排与人工复核一致 |
| OCR 分析耗时 | 380 ms | 228 ms | 单次 v13 目标用例 |
| 本地回填与 PNG 编码 | 487 ms | 1449 ms | 字形 mask、邻域恢复、排版与编码 |
| 单页端侧视觉总耗时 | 867 ms | 1677 ms | 不包含远端 LLM 翻译时间 |
| 改动画素比例 | 1.035% | 0.782% | 只衡量覆盖范围，不代表美观 |
| 输出 PNG | 3.13 MiB | 2.92 MiB | 无损测试产物 |

PSS 是测试进程阶段样点：两页渲染后分别约为 136 MiB 与 167 MiB，且 GC 会使阶段后数值低于阶段前；它
不能被解释为漫画翻译的独立峰值或增量。渲染器持有一张可编辑 RGBA PixelMap，并对单个有界文字区域读取
像素以建立 mask；没有额外保留整页 RGBA 副本。长图真实峰值、热降频和连续多页资源回收仍需单独测量。

## 真实 Reader 补充（2026-07-22）

设备 `237` 上用实际日文画廊补做了默认端侧路线，不配置 sidecar，只选择共享 Codex 源
`gpt-5.6-luna`。第 1 页系统 OCR 输出 10 个区域，第 2 页输出 7 个区域；第 2 页首次 OCR、远端逐块翻译、
端侧渲染到 Reader ready 约 16.6 秒。复用已有翻译文档只重做第 1 页端侧渲染约 1.8 秒；进程重启后同页
持久衍生页命中从 source identity 解析到 ready 为 8 ms，日志为 `cache=1`，没有再次运行 OCR 或 LLM。

生产 analyzer/render 现升至 v14/v19。v14 会把同一气泡中被系统 OCR 拆开的相邻纵列、横行重新合并，v19
按合并后的气泡空间统一拟合字号，不再逐行各算一套大小。实际日文页中，第 1 页 `な、なんで` 与后续正文、
横排叙述均已形成单一布局块；第 2 页 `はい。` 与 `洗うから後ろ向いて。` 已按同一气泡、同一字号排版，未再
出现同气泡字号跳变和译文相压。纵排原文处理仍只扫描原文字形附近，不会把扩大的排版区域整块抹白。

![Reader 第 1 页 v19](assets/manga-translation-local-reader/page-01-v19.jpg)

![Reader 第 2 页 v19](assets/manga-translation-local-reader/page-02-v19.jpg)

真实 Reader 已验证原图/译图切换、翻页返回、双击缩放和拖动平移，译文和页面作为同一张衍生 PNG 工作。
当前明确未解决的是第 2 页小气泡 `え?` 的 OCR 漏检，以及一处 `なぜか` 注音残留；两者都不能再靠扩大
圆角遮盖解决，分别需要漫画专用 region detector/OCR 与更可靠的文字 mask。

本次还固定了衍生页落盘契约：端侧后端只能发布 repository 管理的
`comic-translated-pages/<identity>-<artifact>.png`，路径与内容 hash 不匹配会在 Reader 发布前失败。该规则
防止“本地已经生成图片”被误当成可缓存、可恢复的 Reader 产物。

## 真实英文 Reader 补充（2026-07-23）

设备 `237` 对实际日文画廊第 1 页改用英文目标做了连续 v27–v31 复核。v27 直接沿用源纵排方向，导致英文
逐字竖排；v28 改成横排后仍把同一段落的 OCR 大块和内部小块重复绘制；v29 又错误合并左右两个独立段落。
v30/v31 最终采用以下边界：源 geometry 只负责清理，目标语种决定排版；被大段落包含的重复小块在渲染时
抑制；相邻源纵列只在有限水平间距内合并。页面文档仍保留 12 个翻译块，不为排版修复重新调用 LLM。

v31 把白色描边 pen 从最多 1.6 px 改为字号的 20%（限制 2–10 px）。由于深色填充会覆盖描边内侧，复杂
灰阶背景上最终留下的可见白边约等于一层正常字笔画；同一确定性规则同时用于横排和纵排。设备直接产物
为 1,171,810 bytes，artifact 前缀 `a1ceffbc38d3`。从 source identity 解析到 `reader_page_ready` 约 13.0 秒；
其中 detector 返回 32 个区域，补充 OCR 尝试 3 个、接受 0 个，text mask 约 0.94 秒，六个 AOT inpaint
区域合计约 7.26 秒。

v31 的包含块抑制只比较 geometry，会把“落在段落内、但译文并不重复”的小块也静默丢掉。v32 改为单一
区域 owner：已由大块译文表达的子块才抑制，独有子块先合入 owner 再停止单独绘制；拉丁文本按单词边界
比较，`Very` 不会误判为已包含在 `every` 中。横排目标同时加入安全页边距，并限制左右页区域不得越过
各自原始内边界。设备 `237` 上显式从 Torii 切回端侧后复用同一英文文档，真实 Reader 恢复了 `Very`、
`As a rule, condoms...`、`Who could “that guy” be...?` 和右侧压力段落，左下段落也不再贴住物理页边。
确定性回归为 12/12；signed app、signed `entry@ohosTest` 与 V2 inventory 均通过。

v33 将这条边界前移到翻译之前。同一 OCR tile 内，被明显更大纵排段落包含的窄纵列不再作为独立翻译块；
其中未在父段落出现的原文先并入父段落，再由 LLM 生成一份完整译文。设备 `237` 对同一第 1 页执行了新的
端侧识别、翻译和制图，左侧 `Very` / `As a rule` / `Who...` 短句堆叠消失，右侧仍保留“每天用于缓解
压力”的补充语义。该结果说明嵌套 OCR 的根因在分析/翻译边界，而不是继续在渲染后拼接短句。目标设备
回归仍为 12/12，signed app、signed `entry@ohosTest` 与 V2 inventory 均通过。

v36 修正横排空间计算中的独立缺陷：历史 360 px 扩展上限不再反向缩窄本来就更宽的源段落；实际宽度超过
360 px 时，额外宽度只用于减少换行，单块字号仍以 360 px 参考宽度拟合，不能随矩形变宽而增大。设备
`237` 复用同一 v20 英文文档重排后，左上段落从约 360 px 恢复到接近 435 px 源宽，行数和垂直占用下降，
右侧与左下段落保持稳定；目标设备回归升为 13/13，signed app、signed `entry@ohosTest` 与 V2 inventory
均通过。

v37 在原文处理全部结束后，只对至少四行且有明显垂直余量的拉丁横排块读取其局部 PixelMap，比较上/中/下
三个候选文字包围盒中的高对比边缘密度。只有候选相对居中的改善超过固定门槛才改变锚点，采样失败则回到
居中，不影响主渲染。真实页只有左上长段落从居中移至顶部，与下方拟声词拉开；右侧和左下保持 v36。
合成密集障碍用例加入后目标设备回归为 14/14。

v21 analyzer 在分组后增加窄边界页脚过滤，只处理页面底部 6% 内的横排明确网址/平台署名或短符号碎片；
中部网址和底部自然对白的回归用例均保留。设备 `237` 对同一真实页重新分析后，v20 的 7 个块中 3 个页脚
误识别不再进入 v21 文档，4 个正文块全部保留，并记录
`local_non_dialogue_footer_filtered: Ignored 3 likely non-dialogue footer artifact(s).`。页脚作者署名仍以原图
像素显示，这是预期保真结果，不是等待回填的翻译块。目标设备回归升为 15/15。

视觉结论仍是 **未达到生产可用**：v33 已消除重复短句，v36 已修复宽段落被错误压窄，v37 只加入有限的
边缘感知纵向锚点，v21 只排除窄边界内的非对白页脚块；它们不是人物分割、语义障碍检测、二维自由布局或
通用艺术字/拟声词识别。v30 完成时
还触发过 `THREAD_BLOCK_6S`，当时进程 RSS 约 1.95 GiB，主线程
停在结果完成后的系统 Toast 路径；Reader 现取消这条冗余成功 Toast，只保留结果图片和错误反馈。v31 在
ready 后继续响应控件点击并保持进程存活，但单次未复现不能替代连续页峰值内存与 appfreeze 回归门。

## 漫画 detector 端侧移植试验（2026-07-22）

已从 Docker 对照链路单独提取 YSGYolo 1.2 OS1.0 detector，并转换成现有 HarmonyOS ncnn 运行时可加载的
`param/bin`。这里只移植独立模型和前后处理契约，没有把上游 Python、FastAPI 或 GPL 应用代码打入 HAP。
模型卡标记为 [MIT](https://huggingface.co/YSGforMTL/YSGYoloDetector?not-for-all-audiences=true)，但 checkpoint
内嵌的 Ultralytics 元数据标记为 `AGPL-3.0`。当前分发按更保守的 `AGPL-3.0-only` 处理：NextE 接入代码仍按
项目 MIT 许可，模型资产在独立 model-pack 中按自身许可、来源、hash 和对应源码分别标注，不能把模型资产
重新标成 MIT。

| 产物 | 大小 | SHA-256 |
|---|---:|---|
| `ysgyolo_1.2_OS1.0.onnx` | 10,838,944 bytes | `6f3202925f01fdf045f8c31a3bf62e6c44944f56ce09107eb436bc5a5b185ebe` |
| ncnn param | 26 KiB | `f3617c7834bf3f7ae67521db908a53709140aeb1c11a02f8c64b7c091b569987` |
| ncnn bin | 10 MiB | `7658e654db1a2e8a77c387607def85d5d297b26f110cc2b334dd52ae17a4fe00` |

转换后输入/输出为 `in0 -> out0`，输出形状为 `[11, 8400]`。ncnn 默认 FP16 storage 会把本模型的最大绝对
误差放大到约 15.204；关闭 FP16 storage/packed/arithmetic 与 packing layout 后，相对 ONNX Runtime 的最大
绝对误差为 0.001312、平均绝对误差为 0.00001466，`atol=1e-3` 一致性成立，因此首个设备 profile 固定为
CPU FP32，不能擅自切回默认 FP16。

临时把转换产物放入显式测试 HAP 后，设备 `237` 在合法 1024 × 1536 原图上返回 5 个去重区域：模型加载
39 ms、首次推理 207 ms、热推理 160 ms；带该临时用例的完整 Hypium 为 253/253。随后模型以
`model-pack-v1.1.2` 独立发布，HAP 不内置二进制；设置页可选下载 10,747,791 bytes，安装时逐文件校验大小
与 SHA-256，缺包或推理失败时无损回退 v14 Core Vision。production `ComicLocalVisualBackend` 只用 detector
OBB 归并系统 OCR 行，不把整块 OBB 当作遮盖或排版矩形，因此不会重新引入粗暴圆角块。

最终分发与安装也在设备 `237` 实测：NextE-Models Actions run `29893521705` 成功创建
`model-pack-v1.1.2` Release；tag 对应提交为 `9f57c3995aa83518f43db48a64cdd560b4fc83c4`。最终 signed app 的
真实下载从 `download_start` 到 `download_success` 约 5.4 秒，校验并原子安装 10,747,791 bytes 后，设置页由
“未安装”切换为 `YSGYolo`。同一最终代码边界的完整设备 Hypium 为 254/254。该结果证明按需模型包可达、
校验与 production 选择生效，不表示 OCR transcript、背景修复或最终排版质量已经达标。

## PP-OCRv5 补充识别移植试验（2026-07-22）

第二个端侧组件采用官方 `PaddlePaddle/PP-OCRv5_mobile_rec`，固定 source commit
`682f20538d8c086cb2128e5cfac775e6c4904e85`，按 Apache-2.0 单独记录。官方 Paddle inference 文件经
`paddle2onnx 2.1.0` 与 `pnnx 20260526` 转为 CPU FP32 ncnn；Runtime 不包含 Paddle Python 依赖。

| 产物 | 大小 | SHA-256 |
|---|---:|---|
| ncnn param | 19,637 bytes | `7be8d21064ec730db52c03b144b57f6022ecdd1703e1fe410ca209c2bf0e4d47` |
| ncnn bin | 16,442,228 bytes | `1d73b6e2ee6cbd02cabfac6ef9b6a48e62ae76ae02200ea23ac57b121e29697c` |
| 字典 | 74,012 bytes | `d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b` |

桌面 ncnn 对 12 个手工隔离、覆盖三种方向的合法文本行，最佳方向严格转录为 7/12，平均最佳相似度
0.797222，平均推理 16.251 ms；与 Paddle 输出的转录一致性为 33/36。设备 `237` 的直接 NAPI 测试识别
`月影駅東口`、`午後七時雨`、`七月二十日`，模型加载 53 ms，推理分别 162/46/47 ms。纵向样本虽转录正确，
置信度只有 0.736，因此 production 的 0.85 安全阈值会拒绝它：当前策略优先防止错误文字进入翻译和制图，
不把“模型能猜中”误写成可接受结果。

production 仍以 Core Vision 为主，只对 YSGYolo 已检测、且没有任何系统 OCR 行归属的区域调用 PP-OCRv5；
它不会改写已有 transcript。首批拟声词样本仍未闭环：一处只得到 0.608，另一处未被 detector 覆盖，所以
本次不能声称拟声词或艺术字问题已经解决。`model-pack-v1.1.4` Release run `29898205012` 成功，tag 解引用到
`312bbe09df402b9615b2ffbc150115d2e5a7284a`；从 Release 重新下载的三份资产大小和 hash 与上表完全一致。
最终 signed app 已在设备 `237` 通过设置页安装该 Release，状态由“未安装”切换为
`YSGYolo + PP-OCRv5`；该状态只在五份 detector/recognizer 资产逐文件通过大小与 SHA-256 后发布。最终
`ComicLocalVisualBackend` 目标用例为 6/6，设备完整 Hypium 为 256/256。ohosTest 与正式应用数据目录隔离，
因此不把测试模块读取正式安装目录作为验收方式；正式模型位由生产下载校验与同设备直接 NAPI 测试共同覆盖。

## 长图 detector 分块（2026-07-22）

旧实现只按 16 MP 总像素数决定是否调用 detector，导致 `720 × 14804` 这类 10.7 MP 长图被整体压入
640 × 640 letterbox，实际文字宽度只剩约 31 px。当前 profile 改为 2048 × 2048、256 px 重叠分块，逐块
OBB 回映原图后按同类中心距离 `< 10 px` 或轴向 IoU `> 0.3` 去重；上限为 64 块和 512 个区域，任一分块
失败即整页回退 Core Vision，不发布不完整 detector 结果。生产 YSGYolo profile 升为
`ysgyolo-1.2-os1-ncnn-fp32-tiled-v2`，revision 升为 2，使旧页面缓存自然失效。

设备 `237` 的离线 `720 × 4608` fixture 被切为高度 `2048/2048/1024` 三块，跨块重复 OBB 合并后得到 3 个
原图区域，最大 Y 坐标为 3834，验证了重叠、去重和坐标回映。临时真实发布模型探针另用 `720 × 14804`
合成长图跑 9 块 ncnn 推理：模型加载 48 ms，总推理 1731 ms，目标用例 7/7；探针和测试沙箱模型随后移除，
正式测试只保留离线 fixture。合成白页没有文字，因此该数据只证明长图资源边界和推理稳定性，不证明真实
长图 region recall、OCR 或最终制图质量。

## 当前缺口与后续门槛

下一阶段不能继续靠扩大启发式来掩盖根因，必须以漫画专用 detector/OCR 和内容感知修复补齐能力：

1. 扩展到至少包含横排、纵排、多列气泡、彩色页、低清扫描、倾斜字、描边字和复杂拟声词的合法评测集；
2. 单独报告 region recall、OCR transcript、方向/阅读顺序、残留原文、遮盖越界和排版 overflow，不能只报
   一个总准确率；
3. 扩大真实 Reader 样本并分别统计 LLM、端侧视觉和缓存命中的 P50/P95；缓存命中继续禁止重新 OCR 或
   调用 LLM；
4. 在普通页、长图和连续多页场景记录 P50/P95、峰值 PSS、失败回退与热稳定性；
5. 在已发布 detector、补充 recognizer 与 Core Vision OCR 行归属基础上补齐长图分块、扩展样本和持续
   性能门；资源缺失、低置信度或推理失败继续无损回退当前系统 OCR；
6. 只有拟声词/艺术字覆盖、复杂背景修复和跨样本视觉复核通过后，才允许关闭 B2/F 的 V1 质量项。
