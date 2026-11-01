# 工程技能包

本目录提供 13 个可独立使用的工程技能，覆盖问题诊断、性能分析、软硬件构建、接口与数据完整性、Linux 运行和协作交付。每个技能使用标准 `SKILL.md` 入口，配套参考、脚本与资源位于同一文件夹内；使用时复制完整文件夹。

## 用途索引

| 技能 | 用途 |
| --- | --- |
| [systematic-debugging](systematic-debugging/SKILL.md) | 核实故障观测、定位首个失败边界、设计判别实验并验证修复 |
| [performance-bottleneck-analysis](performance-bottleneck-analysis/SKILL.md) | 统一吞吐与延迟口径、定位瓶颈、比较优化前后的正确性和性能 |
| [ai-assisted-engineering](ai-assisted-engineering/SKILL.md) | 明确需求、约束与验收，完成实现、验证和阶段交付 |
| [hardware-build-and-handoff](hardware-build-and-handoff/SKILL.md) | 核对硬件设计、软件接口、构建产物与交付证据是否匹配 |
| [vivado-vitis-flow](vivado-vitis-flow/SKILL.md) | RTL、C/C++ HLS 或受支持的 MATLAB 流程生成 IP，并完成 Vivado 与 Vitis 构建链 |
| [streaming-data-path-verification](streaming-data-path-verification/SKILL.md) | 验证流握手、背压、数据打包、帧边界、复位与跨时钟域行为 |
| [shared-buffer-lifecycle](shared-buffer-lifecycle/SKILL.md) | 检查共享缓冲所有权、DMA 可见性、租约、完成与停止恢复 |
| [ps-pl-interface-contract](ps-pl-interface-contract/SKILL.md) | 检查寄存器、描述符、内存布局、完成语义与事务身份 |
| [camera-hdmi-diagnosis](camera-hdmi-diagnosis/SKILL.md) | 分层诊断摄像头、像素格式、存储传输、处理和 HDMI 输出 |
| [linux-runtime-and-release](linux-runtime-and-release/SKILL.md) | 处理 Linux ABI、驱动和用户态集成、服务策略及分阶段发布 |
| [network-streaming-diagnosis](network-streaming-diagnosis/SKILL.md) | 定位链路、收包、完整帧、缓冲与处理过载问题 |
| [result-association-and-publication](result-association-and-publication/SKILL.md) | 检查解码结果、实体与位置关联、发布队列及显示提交 |
| [algorithm-porting-and-replay](algorithm-porting-and-replay/SKILL.md) | 冻结同一输入，比较算法阶段、数值语义与目标移植结果，回放失败样例 |

## Linux / Ubuntu 安装

在仓库根目录执行以下命令，将全部技能复制到当前项目的技能发现目录：

```bash
mkdir -p .agents/skills
for package in skill/*/; do
    cp -R "$package" .agents/skills/
done
```

只安装某一个技能时，例如：

```bash
mkdir -p .agents/skills
cp -R skill/vivado-vitis-flow .agents/skills/
```

## Windows 安装

在仓库根目录打开 PowerShell，复制全部技能：

```powershell
New-Item -ItemType Directory -Force .\.agents\skills | Out-Null
Get-ChildItem -LiteralPath .\skill -Directory | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination .\.agents\skills -Recurse
}
```

只安装某一个技能时，例如：

```powershell
New-Item -ItemType Directory -Force .\.agents\skills | Out-Null
Copy-Item -LiteralPath .\skill\vivado-vitis-flow -Destination .\.agents\skills -Recurse
```

上述方法仅作用于当前项目。需要跨项目使用时，可将选中的完整技能文件夹复制到个人 `$CODEX_HOME/skills`；未设置 `CODEX_HOME` 时，通常使用用户目录下的 `.codex/skills`。更新已有同名技能前，先比较并保留自行修改的内容。

## 使用方法

在支持技能发现的 Codex 环境中，可按任务自动选用技能，也可显式调用：

```text
$systematic-debugging 分析当前报错，核实实际运行版本并定位首个失败边界。
$vivado-vitis-flow 根据现有源码和本机工具完成硬件与软件构建，检查导出接口及目标 ELF。
$shared-buffer-lifecycle 检查采集、识别与显示共享缓冲的所有权和停止恢复过程。
```

若安装后技能列表未刷新，重新打开项目或客户端。也可直接阅读对应 `SKILL.md`，按当前任务选择所需参考文件。

技能包不附带 Vivado、Vitis、MATLAB 或板端工具链。脚本的输入格式与适用范围见各包参考；静态检查、仿真、目标编译和物理上板分别验证不同边界，使用时记录实际执行的检查。各包的 `references/provenance.md` 说明能力范围与验证限制。
