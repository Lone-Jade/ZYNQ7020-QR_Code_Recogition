# 测试数据

数据按网页纯 PS、网页最终版、真实传送带三类保存，共 18 个 CSV。先查看 [summary.csv](summary.csv)，再按场景进入明细目录。

| 场景 | 目录 | 目标数 | 成功 | 漏检 | 识别率 |
| --- | --- | ---: | ---: | ---: | ---: |
| 网页纯 PS | [web/ps](web/ps/) | 1000 | 909 | 91 | 90.90% |
| 网页最终版 PS+PL | [web/final](web/final/) | 5000 | 4997 | 3 | 99.94% |
| 真实传送带最终版 | [real](real/) | 150 | 150 | 0 | 100.00% |

真实测试的 K5/K6 分组含估算时间，K6 在时间锚点不确定窗口内可确认的目标数为 42～50。表中 150/150 沿用既有分组口径；详细条件见 [metadata/notes.csv](metadata/notes.csv)。

## 文件组织

```text
data/
├── summary.csv                 三类测试总览
├── web/
│   ├── ps/
│   │   ├── groups.csv          每组一行
│   │   ├── targets.csv         每个展示目标一行
│   │   ├── by_speed.csv        按生成器速度汇总
│   │   └── by_speed_k.csv      按生成器速度及源尺寸汇总
│   ├── final/                  与 ps 使用相同的四张表和列结构
│   ├── comparison.csv          原有 1000 个目标的 PS / 最终版配对对照
│   └── source_manifest.csv     外部历史证据来源
├── real/
│   ├── groups.csv              K4、K5、K6 三组统计
│   ├── targets.csv             三组共 150 个展示目标
│   ├── decode_events.csv       连续解码事件，含重复记录
│   └── source_manifest.csv     外部历史证据来源
└── metadata/
    ├── fields.csv              数据字段类型、单位及原字段映射
    ├── notes.csv               测量条件和不确定性
    └── file_mapping.csv        原文件与新文件的对应关系
```

## CSV 规范

- 编码为 UTF-8 BOM，使用逗号分隔、CRLF 换行，首行为唯一列名行，按标准 CSV 规则处理引号。
- 列名统一为英文 `snake_case`。同一数据层级的网页 PS / 最终版表使用完全相同的列结构。
- 共通身份列使用 `scenario`、`version`、`group_id`、`run_id`。目标和事件的共通列还包括 `k`、`payload`。
- 布尔值统一为 `0` / `1`。缺失或不适用的值为空，不能当作零。数值使用十进制小数点，不附单位符号，不额外四舍五入；消除 `6.0` / `6` 这类格式差异。
- 百分比字段以 0～100 保存，如 `99.94` 表示 99.94%。时间戳保留原单位；ISO 8601 时间保留原时区，未将板端单调时钟当作 Unix 时间。
- 历史证据路径统一为 `/` 分隔。`source_manifest.csv` 中的路径指向提交目录外的历史证据归档，所存 SHA-256 是既有来源记录，本次未计算或校验。

## 字段与统计口径

| 旧字段 | 统一字段 | 说明 |
| --- | --- | --- |
| `group` | `group_id` | 场景和版本内的组标识 |
| `pitch` | `k` | 网页目标的源画布像素/模块 |
| `speed` | `generator_speed` | 生成器速度单位 |
| `source_px_per_second` | `source_speed_px_s` | 源画布像素/秒 |
| `reported_processing_fps` | `processing_fps` | 该组记录的处理帧率 |

`k` 的含义依赖场景：网页为源画布像素/模块，真实测试为纸码尺寸标签，两者不能直接当作同一物理量。真实测试保留 `recorded_k`，记录采集时误标的原始标签；实际尺寸使用 `k`。

逐目标记录的身份为 `(scenario, version, group_id, payload)`。真实测试不同组可以使用相同纸码内容；K5/K6 也可以共享同一 `run_id`，因此不能只按 payload 或 run_id 去重。连续解码事件允许相同 payload 多次出现。

`recognized=1` 表示该展示目标至少成功识别一次。`decode_observations` 和连续事件行数包含重复解码，不能直接作为成功目标数。K4 的目标结果来自独立组记录，连续事件表不覆盖 K4。

网页测试由显示器播放后经摄像头拍摄。对照表只比较相同生成序列的原有 1000 个目标，各版本的相机采集独立；最终版完整明细另含追加 4000 个目标。生成器速度乘 135 得到源画布像素/秒，不能换算为实物传送带速度。

汇总处理帧率按各组 `fps_sample_seconds` 加权。网页原有汇总数值保留；真实总处理帧率由三组记录加权计算，约为 28.603 FPS。该统计不代表算法核最大吞吐量。

## 去除重复文件与后续修改

真实 K4/K5/K6 的分表记录已合并到 `real/targets.csv`，需要时按 `k` 筛选。网页漏检目标可从两个 `targets.csv` 中筛选 `recognized=0`，原独立漏检表不再重复保存。旧导出校验 JSON 的组统计已保留在 CSV，其创建时间记录在 `metadata/notes.csv`；已失效的导出文件 hash 不再保留。

本次整理仅统一结构和表示方式，没有重测或补造原始测量值。数据文件的当前 SHA-256 已纳入 `build/MANIFEST.json`，可使用 `python3 -B build/scripts/verify_release.py --hash-only` 校验。历史来源清单中的 hash 仍为原始记录；文档不参与 Hash 校验。
