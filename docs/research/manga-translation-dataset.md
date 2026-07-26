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
- layout 数量、analysis/render/AOT 耗时；
- 显式开启 `--include-text` 时的 OCR 原文、规范化原文、译文和 block kind。

这些字段可以自动生成，因此以后修改检测、OCR、布局或修复时可以统一跑回放，不需要重新抄写截图结论。

已有原创两页 fixture 的严格 transcript/术语真值可直接评分：

```bash
python3 scripts/comic_dataset_score.py \
  --inventory .hvigor/outputs/comic-dataset/inventory-v1.json \
  --reference-manifest entry/src/ohosTest/resources/rawfile/comic_translation_eval_manifest.json \
  --output .hvigor/outputs/comic-dataset/original-v1-score.json
```

评分器逐 recording 输出 source recall/precision、漏检、误检、阅读顺序错误和必需术语错误。它不会将
像素变化、provider confidence 或同一页的候选重跑伪装成翻译准确率。

2026-07-26 首次真实盘点得到 34 个唯一页面、250 次 recording observation；其中 catalog 已分配
4 个公版训练页、5 个公版开发页、3 个独立 Turok holdout 页，余下 22 页在来源或真值整理完成前保持
`unassigned`。同一图片的基线/候选重跑按 SHA-256 合并，未被计为额外训练样本。原创两页的严格自动基线为
source recall 81.82%（9/11）、source precision 100%（9/9）、阅读顺序错误 0、必需术语错误 0；两个漏检
均为已知融入画面的拟声词。该数字只代表已审核的原创 fixture，不外推成真实漫画总体 OCR 或翻译准确率。

## 必须人工补充的真值

自动录制不能拿来训练自己。每个被抽样标注的页面/区域至少需要：

- 文本区域 polygon、是否应处理、`dialogue/caption/sfx/artwork` 类别；
- 审核后的原文 transcript；
- 允许有多个等价表达的目标译文或语义判定；
- 原文残留、越界、重叠、平块修复等视觉标签；
- 授权/来源和禁止导出的范围。

## 训练与评测的边界

第一轮不训练“端到端漫画翻译模型”。数据按能力拆分：detector 用区域/类别标签，OCR 用图块与逐字真值，
mask/inpaint 用区域与视觉标签，LLM 翻译用原文、上下文与等价译文判定。每条候选都必须在未参与调参的
画廊级 holdout 上分别报告 OCR、SFX false-positive、翻译、布局和视觉指标；像素变化百分比不能代替翻译
准确率。
