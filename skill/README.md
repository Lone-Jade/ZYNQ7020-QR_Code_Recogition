sshiji

# 工程技能包

本目录收录 13 个可独立使用的工程技能包，覆盖问题诊断、性能分析、软硬件构建、接口与数据完整性、Linux 运行和交付。每个技能包都是自包含的文件夹，由 Markdown 文档与可选的 Python 脚本组成；脚本只使用 Python 标准库，阅读与执行都不需要网络、服务或专有工具。

## 组成结构

每个技能包以 `SKILL.md` 为入口，并按需附带下列目录（并非每个包都齐全）：

```text
<skill-name>/
├── SKILL.md            入口：适用范围、步骤与判定标准
├── references/         背景资料、判据、格式说明与能力边界
├── scripts/            可单独运行的检查脚本（仅用标准库）
└── assets/             模板、样例或 testbench
```

`SKILL.md` 开头的元数据只描述技能名称与适用场景，声明的是任务边界而不是运行环境依赖。

## 用途索引

| 技能                                                                             | 用途                                                                        |
| -------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| [systematic-debugging](systematic-debugging/SKILL.md)                             | 核实故障观测、定位首个失败边界、设计判别实验并验证修复                      |
| [performance-bottleneck-analysis](performance-bottleneck-analysis/SKILL.md)       | 统一吞吐与延迟口径、定位瓶颈、比较优化前后的正确性和性能                    |
| [ai-assisted-engineering](ai-assisted-engineering/SKILL.md)                       | 明确需求、约束与验收条件，组织实现、验证和阶段交付                          |
| [hardware-build-and-handoff](hardware-build-and-handoff/SKILL.md)                 | 核对硬件设计、软件接口、构建产物与交付证据是否匹配                          |
| [vivado-vitis-flow](vivado-vitis-flow/SKILL.md)                                   | RTL、C/C++ HLS 或受支持的 MATLAB 流程生成 IP，并完成 Vivado 与 Vitis 构建链 |
| [streaming-data-path-verification](streaming-data-path-verification/SKILL.md)     | 验证流握手、背压、数据打包、帧边界、复位与跨时钟域行为                      |
| [shared-buffer-lifecycle](shared-buffer-lifecycle/SKILL.md)                       | 检查共享缓冲所有权、DMA 可见性、租约、完成与停止恢复                        |
| [ps-pl-interface-contract](ps-pl-interface-contract/SKILL.md)                     | 检查寄存器、描述符、内存布局、完成语义与事务身份                            |
| [camera-hdmi-diagnosis](camera-hdmi-diagnosis/SKILL.md)                           | 分层诊断摄像头、像素格式、存储传输、处理和 HDMI 输出                        |
| [linux-runtime-and-release](linux-runtime-and-release/SKILL.md)                   | 处理 Linux ABI、驱动和用户态集成、服务策略及分阶段发布                      |
| [network-streaming-diagnosis](network-streaming-diagnosis/SKILL.md)               | 定位链路、收包、完整帧、缓冲与处理过载问题                                  |
| [result-association-and-publication](result-association-and-publication/SKILL.md) | 检查解码结果、实体与位置关联、发布队列及显示提交                            |
| [algorithm-porting-and-replay](algorithm-porting-and-replay/SKILL.md)             | 冻结同一输入，比较算法阶段、数值语义与目标移植结果，回放失败样例            |

## 使用方式

技能包不与任何软件或运行环境绑定，按下列任一方式使用即可：

1. **直接阅读**：用任意 Markdown 阅读器打开对应 `SKILL.md`，按文中步骤执行；需要细节时打开同包的 `references/`。
2. **纳入工程**：把完整的技能文件夹复制到自己的工程、知识库或笔记目录，保留包内相对结构，因为文档之间的相对链接依赖它。
3. **运行脚本**：在技能包目录执行 `python3 scripts/<脚本>.py --help` 查看参数。脚本只读取给出的输入文件并打印检查结果，不修改仓库、不访问网络；输入格式与适用范围见同包参考文档。
4. **按需裁剪**：保留 `SKILL.md` 及其中引用到的文件即可使用；与已有同名技能合并前先备份本地修改。

以下命令在仓库根目录执行。复制单个技能（Linux/macOS）：

```bash
cp -R skill/vivado-vitis-flow /path/to/your/knowledge-base/
```

复制全部技能：

```bash
for package in skill/*/; do
    cp -R "$package" /path/to/your/knowledge-base/
done
```

Windows PowerShell：

```powershell
Copy-Item -LiteralPath .\skill\vivado-vitis-flow -Destination <目标目录> -Recurse
```

```powershell
Get-ChildItem -LiteralPath .\skill -Directory | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination <目标目录> -Recurse
}
```

技能包不写入任何配置目录、不注册服务、不修改环境变量；如何归档、分发或集成完全由使用者决定。

## 使用边界

- 技能包不附带 Vivado、Vitis、MATLAB、板端工具链或 Python 第三方库，也不授予硬件、器件或工具链授权。
- 静态检查、仿真、目标编译与物理上板分别验证不同边界；使用时记录实际执行的检查与未覆盖项。
- 各包的 `references/provenance.md` 说明能力范围、来源与验证限制。
- 文档描述的是通用工程方法与判据，不替代实际测量、完整实现审查或实际板测。
