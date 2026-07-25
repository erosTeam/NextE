# 漫画翻译视觉回归工作流

- **状态**：开发评测底座；指标不能单独替代真实视觉验收
- **首次建立**：2026-07-24
- **入口**：`scripts/comic_visual_regression.py`
- **适用范围**：端侧检测、容器、消字、排版和最终译图的真实页面回归

## 目的

端侧视觉调整不能继续依赖“安装应用 -> 打开 Reader -> 翻到指定页 -> 等待翻译 -> 截图 -> 肉眼比较”
作为每轮主反馈。开发工作流需要把一次真实运行录制为可离线重放的阶段产物，并只让人工复核自动评分发现的
变化区域。

本工作流不把生成图片当作真实质量证据。仓库内原创 fixture 继续承担确定性单元/集成回归；用户授权的真实
漫画页承担视觉质量回归，两者不能互相替代。

## 样本分层

| 集合 | 建议规模 | 标注深度 | 运行时机 |
|---|---:|---|---|
| Core | 12 页 | 完整文字、容器 mask、动作与排版边界 | 每个视觉候选 |
| Regression | 约 48 页 | 类别、容器类型和严重缺陷 | 阶段完成 |
| Holdout | 约 30 页 | 与 Regression 相同，但开发时不可查看 | 里程碑 |
| Performance | 100–200 页 | 不要求精细视觉标注 | 性能与稳定性阶段 |

样本按画廊隔离，不能把同一画廊的相邻页拆到调优集和保留集。优先增加类型覆盖：黑白/彩色、闭合/开放
气泡、文字贴图、稀疏/高密度、多列、横排/竖排/混合脚本、对白/拟声词和普通页/长页。

真实图片、裁片、OCR 文本、译文、画廊标识和内容 hash 只保存在 `.hvigor/outputs` 或其他本地临时目录，
不得提交。持久文档只记录匿名类别、聚合指标和结论。

## 本地 manifest

manifest 使用 schema v1。路径可以相对 manifest，也可以是绝对本地路径：

```json
{
  "schemaVersion": 1,
  "fixtureSetId": "local-authorized-real-pages-v1",
  "candidateId": "container-mask-prototype-v1",
  "thresholds": {
    "pixelDelta": 24,
    "nearWhite": 245,
    "sourceWhite": 235,
    "flatBlock": 12,
    "textureStd": 20,
    "flatStd": 5,
    "minimumComponentPixels": 24
  },
  "pages": [
    {
      "id": "color-open-01",
      "category": "color-open-or-text-on-art",
      "source": "inputs/color-open-01-source.png",
      "candidate": "inputs/color-open-01-candidate.png",
      "baseline": "inputs/color-open-01-baseline.png",
      "allowedMask": "annotations/color-open-01-allowed.png",
      "glyphMask": "annotations/color-open-01-glyph.png",
      "containerMask": "annotations/color-open-01-container.png",
      "comparisonRect": [0, 120, 1320, 1980]
    }
  ]
}
```

- `comparisonRect` 用原图像素坐标排除 Reader 顶栏、底栏或其他不属于漫画页面的区域。
- `allowedMask` 是可选的灰度图，尺寸必须等于原图；值至少 128 的像素允许被候选修改。
- `glyphMask` 是可选的灰度图，尺寸必须等于原图；报告会把值至少 128 的像素以青色叠加到 source，
  用于判断检测到的字形与残留源字、白描边及修复块之间的关系。
- `containerMask` 是可选的灰度图，尺寸必须等于原图；报告会以绿色显示检测或标注的容器，并计算
  容器覆盖、容器外改动和 glyph 位于容器外的比例。没有容器的页面不显示这些字段。
- `baseline` 是可选旧译图，用于同一页的像素变化参考；跨运行的指标比较使用
  `--baseline-report`。
- source/candidate 必须是同一页、同一尺寸、同一内容视口。无法确认身份的配对必须先排除，不能用异常
  大的像素差继续调参。

## 运行

脚本依赖 Pillow 与 NumPy。使用隔离的开发 Python 环境：

```bash
python3 scripts/comic_visual_regression.py \
  --manifest .hvigor/outputs/comic-visual-regression/manifest.json \
  --output .hvigor/outputs/comic-visual-regression/baseline

python3 scripts/comic_visual_regression.py \
  --manifest .hvigor/outputs/comic-visual-regression/manifest.json \
  --baseline-report .hvigor/outputs/comic-visual-regression/baseline/report.json \
  --output .hvigor/outputs/comic-visual-regression/candidate

python3 scripts/comic_visual_regression.py \
  --recording-dir .hvigor/outputs/comic-local-visual-recordings/<recording-id> \
  --fixture-set-id <stable-local-fixture-set-id> \
  --output .hvigor/outputs/comic-local-visual-recordings/<recording-id>-report
```

输出包括：

- `report.json`：逐页、分类和总体指标，可供后续门禁消费；
- `report.html`：source/glyph mask/container mask/baseline/candidate/overlay 对照；
- `assets/`：有界缩略图。黄色表示变化，红色表示新增近白像素，紫色表示源纹理在候选中塌缩为平块。

## 指标解释

- `changedPercent`：超过颜色差阈值的像素比例，只表示改动范围，不表示质量；
- `introducedWhitePercent`：源图并非近白、候选变为近白的改动比例；
- `largestIntroducedWhiteComponentPercent`：最大连续新增白区，可用于发现大块平涂；
- `flatnessCollapsePercent`：源图有明显局部纹理、候选变成低方差平块的区域；
- `outsideAllowedPercent`：发生在人工或模型确认容器之外的变化；有 `allowedMask` 时这是破坏性修改的
  首要指标；
- `glyphMaskPercent`：CTD 字形掩膜占页面的比例；
- `changedInsideGlyphPercent`：字形掩膜中实际发生明显像素变化的比例；它用于发现消字遗漏，不表示
  掩膜外白描边或背景是否被正确处理；
- `containerMaskPercent`：当前检测或标注容器占页面的比例；
- `containerDetections` / `containerConfidence*`：recording 中观测到的容器数量及启发式置信度分布；
  报告暂以 0.65 仅做“高置信度候选”分层，不能据此宣称模型已校准；
- `containerCandidateLayoutPercent`：检测候选数相对实际绘制 layout 数的比例，只表示观测覆盖，不是
  container recall；没有独立人工容器标签时不得把两者混用；
- `rawCoverage` / `solidity` / `areaRatio` / `luminanceStd`：逐候选记录原文字框被连通内区覆盖的比例、
  连通区紧致度、连通区占探测窗比例和内区亮度标准差。它们用于跨样本校准和解释误检，尚未进入生产接受
  规则；
- `changedOutsideContainerPercent` / `glyphOutsideContainerPercent`：相对当前容器并集的页级诊断。
  当容器只覆盖部分 block 时，这两个值会自然偏高，不能当作全页精度；
- `baselineReportDelta`：同一 fixture set 相对上一份报告的百分点变化。

新增白像素会同时包含合法白色描边，因此不能仅按总量判失败；需要结合最大连续白区、纹理塌缩和
`allowedMask`。无容器标注时，报告只能做问题排序，不能宣称“无气泡外修改”。AOT 修复真实感也没有
被遮挡背景真值，仍需对自动筛出的变化裁片做少量人工复核。

## 录制与重放边界

每次完整设备运行最终应产出一个本地 recording：

```text
source image
analysis document
translation batch
glyph mask
container mask
layout boxes
rendered image
stage timings and memory samples
```

重放分四档：

1. analysis-only：验证检测/OCR、阅读顺序和分类；
2. container-only：验证容器召回、IoU 与边界泄漏；
3. render-only：冻结文档和译文，只测试消字与排版，不调用 LLM；
4. full-pipeline：里程碑时运行真实端到端链路。

渲染调整默认使用 render-only；只有分析协议或 prompt 变化才重新运行对应上游。这样可以把付费调用、
远端长尾和设备导航从大部分视觉迭代中移除。

## 首轮基线

2026-07-24 使用已有本地真实 Reader 截图建立了首个未标注 smoke：一页规整黑白闭合气泡、两页彩色
高密度多列、两页彩色开放/文字贴图，共五页。扣除 Reader chrome 后，改动画素为 7.2530%，新增近白像素
为 3.2960%，纹理塌缩为 1.5434%。黑白页最大连续新增白区明显小于彩色开放页，与人工观察方向一致。

另一组文件名标为同页的 source/candidate 实际画面身份不一致，像素变化达到 69%；它已从基线排除。该反例
说明后续 recording 必须携带稳定 source identity，并在评分前校验，而不能只依赖人工文件名。

这五页只是评测器 smoke，不是 Core-12，也没有 `allowedMask`，因此不能作为端侧 V1 的通过结论。下一步是
从真实运行导出原始页面与阶段 mask，完成 Core-12 的一次性标注。

## 端侧 recording v1

2026-07-24 已实现默认关闭的 `ComicLocalVisualRecordingSink`。正常 Reader 构造不注入 sink，因此不会
新增设置项、磁盘副本或运行时上传；只有测试/开发调用显式创建 `ComicLocalVisualFileRecorder` 时，才在
应用 cache 为每次 analysis/render 配对写入独立目录。

当前 recording 包含：

- 原始页面副本、analysis document 和 adapter template；
- translation batch、最终译图和稳定 render identity；
- CTD glyph mask 原始字节及尺寸；
- page-level 容器二值并集、候选标签图，以及 layout 到标签、置信度、原框覆盖率、连通区紧致度、
  探测窗面积占比和内区亮度波动的映射；
- 每个实际绘制组的 source/treatment rect、最终 text rect、字号、描边、书写方向、旋转和颜色；
- analysis 与 render 的逐阶段耗时。

离线脚本会把 recorder 的 `glyph-mask.u8` 严格按记录尺寸还原为 PNG，并在 source 上以青色显示。原始
mask 使用 0/1 字节，不可直接按普通 0/255 灰度图阈值读取；转换时必须先规范化，且字节数必须恰好等于
宽乘高。

早期 recording 没有 `containerMask`。当前 schema v1 以可选增量字段记录 `container-mask.u8` 和每个
layout 的 `containerConfidence`；后续又增加 `container-labels.u8` 与 `containerLabel`，每个非零字节
对应一个 layout 候选，可单独统计像素面积、置信度和人工标签。旧 recording 仍可读取。离线脚本同时保留
根据实际 treatment/text rect 生成的“本次实现允许修改区”，容器候选与实现自身决策边界不能互相冒充。

设备 `237` 的首个 production-model recording 使用两页仓库原创评测图和一页受控长页验证文件闭环，共
导出 3 组、21 个文件，glyph mask 尺寸分别与 1024×1536、1024×1536、1024×3072 页面严格一致。
render-only 报告中总体改动 0.6052%，新增近白 0.2369%，纹理塌缩 0.0366%，实现决策边界外改动为 0。
该结果只证明 recording、拉取与评分衔接正确，不属于真实 Core-12 质量证据。

生产模型基准通过参数 `comicProductionRecordingId` 显式启用 recording；Hypium 长任务必须同时传
`-s timeout 600000`，不能依赖默认 5 秒超时。真实页面下一步沿用同一格式录制，不再为每轮渲染调整重复
导航 Reader 或调用 LLM。

## 真实五页生产回放基线

同日从用户授权画廊冻结五页真实输入：一页规整黑白闭合气泡、两页彩色高密度多列、两页彩色开放边界或
文字贴图。测试入口在设备上运行生产 YSGYolo、PPOCRv5、CTD 与 AOT；为了冻结视觉下游，它只从既有译图
OCR 重建候选译文，未调用 LLM，因此这组结果只衡量检测、消字、修复和排版，不衡量翻译语义准确率。

生产基线总体改动 6.3929%，新增近白像素 3.9528%，纹理塌缩 1.6156%，实现决策边界外改动为 0。按类别：

- 规整黑白闭合气泡：改动 2.8003%，新增近白 1.3446%；
- 彩色高密度多列：改动 7.7948%，新增近白 5.1054%；
- 彩色开放边界或文字贴图：改动 7.3776%，新增近白 4.5329%。

五页分析加渲染总耗时为 4.985–6.127 秒，中位数 5.339 秒，均值约 5.513 秒。主要端侧瓶颈不是
YSGYolo，而是 AOT（约 2.451–2.827 秒/页）和 proposal CTD（约 1.091–1.323 秒/页）；检测约
0.236–0.300 秒，source OCR 约 0.432–0.757 秒。

glyph mask 可视化确认：彩色字形常由有色核心和很粗的白色外描边组成，CTD 准确覆盖有色核心，却不覆盖
原白描边。AOT 擦除核心后，较短中文会暴露留下的白色轮廓，看起来像云状白块。这不是绘制越过 detector
geometry，也不是简单的圆角矩形填充。

两条候选已经在相同五页上被否决：

1. 对 glyph mask 做通用膨胀并追踪高亮低饱和边缘，新增近白降至 2.9121%、纹理塌缩降至 1.0561%，
   但改动扩大到 8.1167%，render 增至约 5.69–7.39 秒/页，并出现明显 AOT 涂抹和虚构纹理；
2. 在上述掩膜上把长修复区切成 256 px 分段，新增近白为 2.9515%、纹理塌缩为 0.8897%，但总体改动
   仍为 7.9706%，五页回放比生产基线慢约 12 秒，且涂抹和虚构背景仍存在。

因此生产实现保持既有 profile v50 / AOT v29。后续不得重复“继续扩大字形掩膜”这类参数调整：白描边一旦
被纳入移除范围，就变成需要重建的真实背景，而当前 256 px AOT 没有可靠恢复该背景。下一项仍是建立独立、
带置信度的 `containerMask`，再在其约束内比较更合适的有界修复模型或保留原画；在此之前，指标下降不能
替代真实画面复核。

## 容器观测基线

2026-07-24 将现有闭合气泡 flood-fill 从“只返回安全矩形”扩展为可选像素级观测。正常 Reader 没有
recording sink 时，中文竖排仍直接走原生产矩形，不增加像素读取、内存副本或布局变化；显式 recording
才使用独立宽搜索窗探测容器，并把 0/1 掩膜和启发式置信度写入产物。竖排观测不会设置
`shapeConstrained`，所以当前不会改变分组、字号、碰撞或最终译图。

第一轮真实回放验证了原实现只在横排分支执行 flood-fill，五页全部没有容器产物；不能把这种零覆盖误写成
模型结果。修正观测边界后的同一五页回放得到 6 个候选：

- 规整黑白页检测 5 个闭合白底气泡，置信度 0.7082–0.7660，绿色像素掩膜目视贴合气泡内区；
- 一张彩色文字贴图页检测 1 个候选，置信度 0.5460；掩膜沿相似肤色/背景泄漏，目视判定为误检；
- 其余三页没有候选，符合当前算法只识别近似均匀、封闭连通内区，而不覆盖开放边界和文字贴图的能力边界。

黑白页容器并集占页面 9.5032%；彩色误检占 2.1584%。报告中的 0.65 分层在这五页上恰好把 5 个正确候选
与 1 个误检分开，但它只是待校准阈值，不能基于单一画廊直接进入生产。容器观测前后最终译图指标完全一致：
总体改动 6.3929%、新增近白 3.9528%、纹理塌缩 1.6156%，证明本阶段只建立了测量信号。

设备 `237` 的目标回归为 39/39。显式 recording 的五页任务从此前约 30.7 秒增至约 35.5 秒，差值包含
额外逐 block `readPixels` 和运行波动；正常 Reader 不执行竖排观测，因此不能把该差值当作生产性能回退。

下一步不是立刻让 AOT 使用这 5 个气泡，而是把样本扩到 Core-12，按“闭合均匀、彩色闭合、开放/贴图、
高密度/拟声”一次性标注容器存在性和严重误检。只有置信度在跨画廊样本上可分离后，才允许高置信度
`containerMask` 约束修复；低置信度与无容器页继续保留原画或交给云端整图路线。

候选标签图已在同一五页第三轮 recording 验证：黑白页的 5 个候选分别占页面
1.0176%–3.6792%，彩色误检候选占 2.1584%，可以从报告直接定位到独立彩色区域，不再只能查看合并后的
绿色并集。第三轮最终译图指标仍与基线完全一致，设备目标回归维持 39/39。

2026-07-26 的第四轮真实回放保持相同五页与相同最终译图指标，并为 6 个候选补齐诊断特征。目视正确的
5 个黑白闭合气泡为：原框覆盖率 0.7569–0.8076、紧致度 0.6488–0.7227、探测窗面积占比
0.2004–0.3066、亮度标准差 5.2173–6.7691；彩色相似背景误检分别为 0.6169、0.4594、0.1472 和
9.8728。四项在这一个小样本中都存在间隔，但仍不能据此写入生产阈值。五页共有 28 个实际绘制 layout，
仅 6 个产生候选，候选/layout 比例为 21.4286%；它不是 recall。

新增特征只在显式 recording 的 flood-fill 循环内累计。与前一轮同页 recording 相比，五页分析加渲染
均值由 6.6172 秒变为 6.6098 秒，属于运行波动，未观察到可分辨的 recording 性能增加；正常 Reader
仍不运行竖排容器观测。本轮设备目标回归为 39/39，真实回放为 1/1。

本地历史产物盘点发现一些额外真实 Reader 截图，但其中包含英语旧链路、Reader chrome、source/translated
视口不一致或尚未完成翻译的状态。它们只能作为待整理候选，不能为了凑够 12 页直接并入 Core。进入 Core
前必须满足同页身份、稳定内容视口、目标链路一致和类别归属四项检查；否则继续保留在临时证据目录。

## 七页真实彩页容器校准

2026-07-26 从另一组用户授权真实画廊冻结连续七页 1280×1780 彩页，并新增
`comicContainerCalibration` 显式测试模式。该模式从 `ohosTest` 本地资源暂存原图，使用固定占位译文只为
触发生产检测、修复、排版和 recording；它不调用 LLM，也不把占位译图当作翻译质量证据。真实原图和人工
标签继续只保存在忽略目录，不进入仓库。

七页共得到 39 个 layout 和 8 个容器候选。人工复核候选所在的三页后：

- 五个彩色矩形旁白框均为真候选，置信度为 0.7294–0.7984；
- 三个开放式文字/相似背景连通区均为误检，置信度为 0.5065–0.6279；
- 该彩色旁白页目视共有七个应支持的闭合矩形框，当前漏掉两个浅色/灰白框。

因此这一组未分层候选 precision 为 62.5%，recall 为 71.4286%；按报告既有 0.65 分层时 precision 为
100%，recall 仍为 71.4286%。与此前五页中已复核的 5 个黑白真候选和 1 个彩色误检合并，五个已人工
复核页面共有 12 个目标容器、10 个真候选、4 个误检和 2 个漏检：未分层 precision 71.4286%、
recall 83.3333%，0.65 分层 precision 100%、recall 83.3333%。

这个结果说明置信度适合做保守 precision 门，但不能解决浅色闭合框 recall；下一步应补充边框闭合/矩形
面板候选，而不是继续调低 flood-fill 阈值。当前虽已取得 12 页真实输入的数值规模，但只有五页完成容器
人工标签，且没有独立画廊 holdout，因此仍不能把 0.65 或四项诊断特征写入生产接受规则。

同一次设备计时把 analysis/render 分开落入 `timings.tsv`，离线报告会自动读取。七页 analysis 为
2.377–3.016 秒，均值 2.721 秒；render 为 2.317–6.649 秒，均值 4.678 秒；总耗时
5.196–9.312 秒，中位数 7.588 秒、均值 7.399 秒。render 占已测时间 63.2248%，并随 block 数增加，
所以当前性能优化优先级高于继续压缩检测：复用/合并修复工作、减少逐 block 重复 mask/编码开销，必须在
相同真实页上证明画质不回退。

离线脚本新增可选 `--container-review`，会校验每个已复核页的全部候选标签，并报告候选 precision、
recall、高置信分层和漏检数；未带 `timings.tsv` 或 review 的旧 recording 仍可读取。这使后续样本扩充
变成“新增真实页 -> 一次标注 -> 自动聚合”，不再每轮靠临时目测重新统计。

## 矩形边框候选与独立负向留出

同组七页的逐候选失败原因表明，两个漏检都不是搜索窗触边或种子点错误，而是 flood-fill 在透明/场景填充
的矩形旁白框内只能取得过小连通区，统一落入 `area_too_small`。降低 72% 面积门会同时放入大量背景连通
误检，因此新增了第二类、只在 recording 校准模式运行的轴对齐边框候选：仅在 flood-fill 面积不足时向外
搜索四条连续边，四边覆盖率均不低于 0.9 才记录 `accepted_rect_border`。正常 Reader 尚不执行该分支。

同一七页重新回放后只新增两个候选，恰好补回两个漏检，没有在其余页面产生新候选。已复核三页变为
7 个目标全部命中、3 个旧低置信误检，原始候选 precision 70%、recall 100%；按既有 0.65 分层时
precision/recall 均为 100%。这仍是开发集结果，不是独立正向留出。

随后冻结同画廊另一段连续七页作为独立硬负向留出，共 43 个 layout。新矩形边框分支新增候选为 0；
三项既有 flood-fill 候选中只有一个高置信矩形旁白框，另外两个保持低置信。该结果证明当前边框规则在这组
复杂彩页上没有扩大误检，但不证明它能跨画廊召回透明矩形框。生产接管前仍需另一视觉家族或另一画廊的
正向矩形框留出；在此之前该分支保持 recording-only。

## 独立正向留出与边框得分诊断

2026-07-26 冻结 Wikimedia Commons 公版漫画
[Daredevil Battles Hitler](https://commons.wikimedia.org/wiki/File:Daredevil_Battles_Hitler.djvu)
的连续四页作为另一视觉家族的正向留出。四页为老扫描彩页，共人工标注 18 个矩形旁白框；原 flood-fill
得到 9 个真候选、12 个误检和 9 个漏检，precision 42.8571%、recall 50%。0.65 分层 precision
50%、recall 33.3333%，不能通过生产晋级门。

recording 现为每次矩形边框尝试保留四边最高得分和明确拒绝原因。该正向留出共有 21 次尝试：20 次为
`score_too_low`、1 次为 `raw_rect_too_small`，原四边均不低于 0.9 的规则没有新增候选。左、右、上、下
四边均值分别为 0.6287、0.5628、0.7178、0.3741；最弱边均值仅 0.2417。下边明显弱于其余方向，证明
老扫描中的断边、脏污和文字框贴近画格边界会破坏“整条边近乎连续”的假设，不能再靠统一提高搜索窗或降低
flood-fill 面积门处理。

为验证可分性，只在 recording 分支把四边最低覆盖门从 0.9 降到 0.5。同一四页新增两个候选：一个是真
矩形旁白框，另一个是被近似矩形包围的普通气泡，增量 precision 为 50%，只补回 9 个漏检中的 1 个。
整体变为 10 个真候选、13 个误检和 8 个漏检，precision 43.4783%、recall 55.5556%。虽然新增真候选
置信度 0.7478、误候选为 0.6095，但全体候选按 0.65 分层仍只有 53.8462% precision 和 38.8889%
recall，不能把这一局部分离误写成生产质量。

相同 0.5 规则又在前述七页、43 个 layout 的硬负向留出上复跑：11 次矩形尝试全部保持
`score_too_low`，新增候选仍为 0；四边均值为 0.1116、0.1487、0.2391、0.2220。这说明得分能区分这两
组候选，但独立正向召回仍然过低。0.5 继续只用于 recording 候选采样，Reader 生产路径不执行矩形分支。

随后验证了“最低边分数 0.3 + 四个局部角点均不低于 0.35”的 recording 候选。它在硬负向留出仍新增
0，但也把正向留出的 7 个可进入角点检查的候选全部拒绝，新增真候选为 0。老扫描旁白框经常与画格边线
共边、角点断裂，而且四条独立最高分边未必属于同一个闭合矩形；局部四角硬门因此已撤回。最终只保留角点
得分作为诊断，recording 接受规则恢复到四边最低 0.5。下一实验必须追踪属于同一连通轮廓的短线段或成对
平行边，不能再把四条独立峰值和四个理想角点当作闭合矩形。

最终正向留出设备均值为 analysis 2.6730 秒、render 6.7735 秒、总计 9.4465 秒；每页 13 次 AOT，
inpaint 5.3302 秒，占后端 render 的 80.8165%。负向七页仍为每页 6.1 次 AOT、总计 7.8000 秒，
inpaint 占 64.4041%。性能结论保持不变：页内文字越多，逐组 AOT 是首要瓶颈，但不得再次跨独立气泡合并。

## 目标框评审 v2 与扩展边框搜索

候选级 `accepted` 标签只能回答 precision，不能可靠回答某个候选命中了哪个目标，也不能区分容器几何漏检
和上游 OCR 根本没有提供独立文字块。离线报告因此增加 container-review schema v2：

- 每个目标记录稳定 id 和原图坐标 `rect`；
- 候选与目标按交集占较小框面积至少 0.5 做一对一匹配，重复候选不能重复增加 recall；
- 根据 recording 的 `sourceRects` 把目标分为 `eligible`、`merged_source` 和 `missing_source`；
- 同时报告全部目标 recall 与只针对 `eligible` 目标的 recall。schema v1 候选标签仍保持兼容。

对公版老扫描四页重新逐框复核后，原 18 个目标中的 `p13-top-left` 实际是包含人物和场景的整格画面边框，
不是字幕容器；若接受会造成大面积误抹，因此从真值中删除。修正后的 17 个目标里，12 个有独立 source
layout、2 个被 OCR 与相邻文本合并、3 个没有可用 source layout。旧候选命中 10/17，候选 precision/
recall 为 43.4783%/58.8235%；在可由容器阶段处理的目标中命中 10/12，eligible recall 为 83.3333%。

真实失败分析只剩两个容器几何漏检：一个 OCR 原框只有短单行，另一个 flood-fill 触及探测窗边缘。新的
recording-only 候选保持原 3–64 px 搜索为第一遍；只有原规则无法形成候选时，才允许横向 0–96 px、
纵向 0–64 px 的第二遍搜索，同时把短行高度下限从 24 px 收窄到 12 px，并让
`touches_probe_edge` 进入矩形边框诊断。直接从 0 px 全局搜索曾让 OCR 字边压过真实容器边，导致既有
确定性描边矩形回归失败，已否决；两阶段搜索恢复设备目标回归 40/40。

设备 `237` 的四页正向重放补回上述两个目标：命中 12/17，候选 precision/recall 为
46.1538%/70.5882%，eligible recall 为 12/12（100%）。剩余五个目标全部属于上游
`merged_source` 或 `missing_source`，不能再通过放宽容器阈值修复。相同代码在七页、43 个 layout 的
真实彩页硬负向留出上保持 3 个既有普通容器候选，40 次矩形尝试全部 `score_too_low`，矩形分支新增接受
为 0；最终译图像素指标也与旧记录完全一致。

这组结果只证明扩展搜索值得保留为 recording 候选，不授权进入 Reader：全部候选 precision 仍低，四条
最高分边仍可能来自互不相干的轮廓。下一质量阶段分成两条独立工作：容器侧用同一轮廓/成对平行线证据降低
误检；OCR 侧处理 2 个合并块和 3 个缺失块。不得把五个上游漏检重新算作容器算法缺陷，也不得为了追求
17/17 让面板边框或场景结构进入擦除范围。

## 修复阶段调用基线与否决候选

recording 的 render timing 现额外记录实际 AOT 调用次数，并由报告聚合逐页阶段。上述七页硬负向留出的
生产基线平均每页 6.1 个可绘制组、6.1 次 AOT 调用；后端 render 均值 5.0536 秒，其中 layout
1.4527 秒、AOT 3.2090 秒、PNG 编码 0.2609 秒。AOT 占后端 render 的 64.2608%，确认它是当前主要
渲染瓶颈，绘字本身只有约 3 ms。

一个“仅在合并后最长边不超过单块 1.35 倍时合并独立气泡”的候选在相同七页完成 A/B：调用均值由
6.1 降至 5.0，render 均值由 5.0536 秒降至 4.8963 秒，总耗时由 7.6893 秒降至 7.5903 秒。视觉汇总
变化很小：总体改动 +0.0162 个百分点、新增近白 -0.0098 个百分点、纹理塌缩 -0.0018 个百分点；优化前后
候选图平均有 0.4885% 像素差异，最大页为 1.4712%。

这项约 3.1% 的 render 收益不足以改变现有质量边界，而且跨独立气泡共享 AOT 输入域违反 v29
“只有同一已确认闭合气泡才能合并”的约束，因此候选已撤回，生产仍保持独立气泡独立调用。调用计数与阶段
聚合继续保留，供后续比较更小修复模型、同气泡内部优化或调度策略；不得再次把跨气泡合并作为无画质成本的
性能优化。
