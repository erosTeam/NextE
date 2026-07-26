# 漫画翻译真实数据集与自动评测

## 目标

将真实 Reader recording 转化为可重复使用的评测数据，而不是把每次人工看图当作新的实验。录制内容是模型
观察值，不是训练真值；训练或质量结论只能使用经人工确认的独立 label。

当前入口：

```bash
python3 scripts/comic_dataset_inventory.py \
  --recording-root .hvigor/outputs/comic-local-visual-recordings \
  --catalog docs/research/fixtures/comic-recording-dataset-catalog-v1.json \
  --include-text \
  --output .hvigor/outputs/comic-dataset/inventory-v1.json
```

该命令按图片 SHA-256 合并重复回放，保留每一次 analyzer/render observation，并拒绝同一图片跨 family 或 split。
catalog 必须按画廊或视觉家族分配 `train`、`dev`、`holdout`；禁止按相邻页面随机切分，避免同一角色、同一
扫描风格和连续上下文泄漏到 holdout。

## 已自动记录的观察

- 页面 identity、尺寸、录制路径和 artifact 文件；
- analyzer/profile、block 数量、SFX/普通文本类别、source origin；
- 翻译源/模型/prompt/context 的不可变身份，以及每个最终 layout 的 source/treatment/text
  矩形、书写方向、字号、描边与容器标签；
- layout 数量、analysis/render/AOT 耗时；
- 显式开启 `--include-text` 时的 OCR 原文、规范化原文、译文和 block kind。

这些字段可以自动生成，因此以后修改检测、OCR、布局或修复时可以统一跑回放，不需要重新抄写截图结论。
它们仍全是候选观察：标签模板只把对应 layout 附在 candidate 下供审核，不会把 OCR、译文、字体或矩形
静默写进 truth。这样一次真实页评审可以明确定位到“上游转录、某次翻译请求或最终回填”的哪一层。

在标签尚未完成前，可用下面的本地 triage 只按可观察风险排序真实录制：先看已经跳过的组、实际 text
rect 相交、没有闭合容器证据和异常小字号。它按源页 identity 去重，只保留该页风险最高的一次观测和相关
录制数，避免基线/候选重放反复占用审核时间。它不输出“质量分”、不决定训练集，也不替代人工视觉真值：

```bash
python3 scripts/comic_dataset_triage.py \
  --inventory .hvigor/outputs/comic-dataset/inventory-v1.json \
  --output .hvigor/outputs/comic-dataset/triage-v1.json
```

同一页的历史 baseline、开发候选和当前 profile 不能混入一次复核。需要只看某次新运行时，显式以 recording
前缀筛选；同时给出 profile 前缀时两者都必须匹配：

```bash
python3 scripts/comic_dataset_triage.py \
  --inventory .hvigor/outputs/comic-dataset/inventory-v1.json \
  --recording-id-prefix real237-20260726-color-core- \
  --output .hvigor/outputs/comic-dataset/color-core-triage-v1.json
```

输出会记录 selection 和 `selectedObservations`。未指定筛选时仍保留原来的全量盘点行为；筛选为空会失败，
不能静默回退到别的历史输出。

已有原创两页 fixture 的严格 transcript/术语真值可直接评分：

```bash
python3 scripts/comic_dataset_score.py \
  --inventory .hvigor/outputs/comic-dataset/inventory-v1.json \
  --reference-manifest entry/src/ohosTest/resources/rawfile/comic_translation_eval_manifest.json \
  --output .hvigor/outputs/comic-dataset/original-v1-score.json
```

评分器逐 recording 输出 source recall/precision、漏检、误检、阅读顺序错误和必需术语错误。它不会将
像素变化、provider confidence 或同一页的候选重跑伪装成翻译准确率。

性能同样从同一 inventory 生成，按每个 recording 分组，不将基线和候选重跑混为一个平均数：

```bash
python3 scripts/comic_dataset_performance.py \
  --inventory .hvigor/outputs/comic-dataset/inventory-v1.json \
  --output .hvigor/outputs/comic-dataset/performance-v1.json
```

报告对每个 recording 分别给出页面数、block/layout 数，以及 analysis、render、AOT inpaint 的中位数和 P90，
并给出 AOT 调用数、drawable/skipped group 数和每调用的 inpaint 耗时。耗时直接读取 recording 的
`totalMs` / `inpaintMs` 字段；中位数对偶数样本取中间两项的算术平均。

新录制还会分解 AOT 的 native call、模型加载、预处理、推理和后处理累计耗时。旧 recording 不补造这些字段，
报告会显示该项 `count: 0`；只有同一版本、同一页集的新旧 recording 才能用它归因性能变化。

2026-07-26 首次真实盘点得到 34 个唯一页面、250 次 recording observation；其中 catalog 已分配
4 个公版训练页、5 个公版开发页、3 个独立 Turok holdout 页，余下 22 页在来源或真值整理完成前保持
`unassigned`。同一图片的基线/候选重跑按 SHA-256 合并，未被计为额外训练样本。原创两页的严格自动基线为
source recall 81.82%（9/11）、source precision 100%（9/9）、阅读顺序错误 0、必需术语错误 0；两个漏检
均为已知融入画面的拟声词。该数字只代表已审核的原创 fixture，不外推成真实漫画总体 OCR 或翻译准确率。

同日 Turok 三页真实设备基线的中位数为：analysis 2.213 秒、render 4.900 秒、其中 AOT inpaint 4.071 秒
（P90 分别为 2.360、5.503、4.570 秒）。三页分别触发 11、11、10 次 AOT 调用，每次约 367、415、407 毫秒；
当前可量化的端侧瓶颈因此是多小区域的串行修复，而不是检测或 OCR。后续优化应以同一 recording 的页面级
分位数、调用数和视觉 holdout 同时比较，不把单页候选重跑与该基线混合。

2026-07-26 又在用户选定的 237 设备上，以独立 Turok P9 原始页进行同进程重复采样；测试仅冻结译文以隔离
端侧视觉链路，不代表整条翻译耗时。首次冷态为 total 33.689 秒、AOT 30.756 秒，其中 native 模型加载
0.593 秒、推理 28.082 秒。随后两次热态分别为 total 3.260 / 3.457 秒、AOT 2.689 / 2.827 秒，9 个区域的
native 推理为 2.087 / 2.253 秒（约占热态整页 64% / 65%，占 AOT 78% / 80%）。因此当前优先级是减少 AOT
推理工作量或替换/优化其模型；ArkTS 桥接、文本绘制和编码不是首要瓶颈。该采样不是跨设备、跨页集的 P50/P95，
不与前述三页基线混算。

同设备、同一冻结 Turok P9 页的 FP32 ncnn packing A/B 保留了 FP32 storage、packed 与 arithmetic，只开启
内部 channel packing。基线 AOT 为 2.884 秒（推理 2.253 秒）；两个候选为 2.392 / 2.512 秒（推理
1.893 / 2.001 秒），即 AOT 约 13%–17% 收益。首个候选成图与基线逐像素一致（candidate-vs-baseline
`0.0%`），因此该项作为无视觉语义变更的运行时实现优化保留；它仍不是跨页面 P50/P95。

在该 FP32 packing 基线之上，AOT FP16 storage、packed 与 arithmetic 的两次候选为 AOT 1.431 / 1.407 秒、
推理 0.954 / 0.941 秒，较未启用 FP16 的同页基线约快 49%–51%。视觉回归在 `pixelDelta=24` 下仍为
candidate-vs-baseline `0.0%`；逐像素对比有 31,636 / 1,306,560 个像素的舍入差，最大单通道差 22、均值
0.016，只有 13 个像素超过 16，真实成图复核未见可辨识退化。因此 production source-treatment 升为
`local-ctd-aot-inpaint-v30`，以避免复用旧 FP32 衍生页；该结论仅覆盖这一个真实页和设备，后续仍需多页
P50/P95 与视觉 holdout 验证。

完成 v30 后，同设备又对独立 Turok P5/P6/P9 三页进行冻结译文回放：analysis 为 2.439 / 2.096 / 2.312 秒，
render 为 2.973 / 3.698 / 3.100 秒，视觉链路总计为 5.412 / 5.794 / 5.412 秒。AOT inpaint 为
2.000 / 2.480 / 2.041 秒，native 推理为 1.324 / 1.702 / 1.378 秒，调用数为 11 / 11 / 9；三页中位数分别为
analysis 2.312 秒、render 3.100 秒、总计 5.412 秒、AOT 2.041 秒、推理 1.378 秒，P90 分别为 2.439、3.698、
5.794、2.480、1.702 秒。三张最终成图抽看未见新增大白块或跨气泡污染。它仍不含 LLM 网络翻译，且经历了
多个 profile 版本，不能与旧三页记录直接计算严格的回归百分比；用途是建立 v30 的跨页性能起点。

## 必须人工补充的真值

自动录制不能拿来训练自己。每个被抽样标注的页面/区域至少需要：

- 文本区域 polygon、是否应处理、`dialogue/caption/sfx/artwork` 类别；
- 审核后的原文 transcript；
- 允许有多个等价表达的目标译文或语义判定；
- 原文残留、越界、重叠、平块修复等视觉标签；
- 授权/来源和禁止导出的范围。

先用下列命令从一个明确的 recording 生成模板；模板中的 candidate 字段只用于减少重复抄录，所有 `truth`
字段初始为空，必须对照原图和渲染结果审核后才可进入评分或训练数据：

```bash
python3 scripts/comic_dataset_label_template.py \
  --inventory .hvigor/outputs/comic-dataset/inventory-v1.json \
  --family turok-596 \
  --recording-id real237-20260726-turok596-baseline-v2 \
  --output .hvigor/outputs/comic-dataset/turok-596-holdout-label-template-v1.json
```

模板同时保留原始 artifact 路径、候选区域 polygon、OCR/译文观察值，并为漏检保留 `additionalRegions`。它不能
自动标注，也不能把 holdout 写回训练集；其作用是让后续审核成为一次有明确输入输出的标注任务，而非临时看图。

审核完成后必须先通过标签校验器，才可作为训练或评测输入：

```bash
python3 scripts/comic_dataset_validate_labels.py \
  --labels path/to/reviewed-labels.json \
  --usage evaluation \
  --require-complete
```

校验器会拒绝未审核/部分填写的 truth、缺少逐字原文或参考译文的可翻译区域、重复区域 ID，以及不符合用途的
split：`train` 只允许训练集、`dev` 只允许开发集、`evaluation` 只允许开发或 holdout。它是数据边界，不会
把模板内容转换或写回任何训练数据。

## 训练与评测的边界

第一轮不训练“端到端漫画翻译模型”。数据按能力拆分：detector 用区域/类别标签，OCR 用图块与逐字真值，
mask/inpaint 用区域与视觉标签，LLM 翻译用原文、上下文与等价译文判定。每条候选都必须在未参与调参的
画廊级 holdout 上分别报告 OCR、SFX false-positive、翻译、布局和视觉指标；像素变化百分比不能代替翻译
准确率。
