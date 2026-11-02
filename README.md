# 高速智能仓储二维码识别系统

本项目是`全国大学生嵌入式芯片与系统设计竞赛——FPGA创新设计赛道——AMD初级赛道`作品。

## 1. 项目简介

> 随着智能仓储与物流向自动化、高速化发展，货物出入库及分拣对二维码读取的实时性、准确性与稳定性提出更高要求。传统工业相机结合CPU工控机的视觉方案在连续高速处理时面临计算负载、设备成本与功耗等挑战。
>
> 本项目基于Zynq-7020/AX7021B，设计面向仓储场景的二维码识别与硬件加速系统。依托PS-PL协同架构，PL完成摄像头采集、灰度处理、候选区域提取、透视网格评分加速及彩色预览与标注叠加；PS/Linux负责系统控制、任务调度、定位后端、最终采样、纠错解码及结果管理。通过流水线评分、整网格作业与独立显示通路提高并行处理效率，减少软硬件交互及ARM显示开销，并利用帧身份校验与缓冲管理保障数据一致性。软硬件一体化设计减少对独立高性能工控机的依赖，具有降低部署成本和运行功耗的潜力。
>
> 最终构建了一套低时延、高可靠的边缘视觉识别系统，在仓储物流传送带仿真网页与真实二维码传送带场景中，经摄像头采集测试，系统总体识别成功率达99.94%，平均吞吐量达27.94 FPS，为智能仓储和自动化物流中的高速信息采集提供了一种可行的嵌入式硬件加速方案。

## 2. 项目基本情况

### 2.1 硬件平台

- 基于AMD Zynq-7000 SoC：Zynq-7020/AX7021B（XC7Z020CLG484-2）
- 摄像头：OV5642 双目摄像头，采用 2 片 OmniVision（豪威）CMOS 图像传感器 OV5640
- HDMI 显示器

### 2.2 设计思路

- PL 完成视频采集、RGB565 直显、Gray8 和候选 ROI 生成、fitness 网格评分及绿色框/文字叠加
- PS/Linux 完成二维码定位、纠错解码、结果关联和运行控制

### 2.3 最终结果

- 摄像头输入为 1280×720、约 30 FPS，HDMI 输出时序为 60 Hz
- 解码成功目标显示绿色框及最多 9 个 ASCII 字符的标签
- 正常启动使用 `sudo zynq-qr start`，每次启动默认启用自动曝光 AEC 和自动增益 AGC，上限为 4 ms、8 倍
- 在传送带仿真网页与真实二维码传送带场景中经摄像头采集测试，系统总体识别成功率达 99.94%，平均吞吐量达 27.94 FPS

## 3. 仓库结构

本仓库的 `main` 是源码复现版本，最终提交仓库地址始终是 <https://github.com/Lone-Jade/ZYNQ7020-QR_Code_Recogition>。

源码只保留可复现设计所需的内容：RTL、HLS、PS/Linux 软件、驱动、必要导出 IP、构建脚本、约束、测试和关键验证记录。Vivado 生成工程、DCP、参考位流/XSA/FSBL/DTB、已编译启动与运行包、Linux SDK 归档均不在源码树内；基础依赖从同一仓库的固定 Release 单独下载（合计约 335 MB，解包后占用数 GiB 工作空间）。

```text
ZYNQ7020-QR_Code_Recogition/
├── README.md               项目说明：结构、构建与使用方法
├── DEPENDENCIES.md         基础依赖的版本、校验与离线导入方法
├── LICENSE                 MIT 许可证
├── .gitattributes          发布文件按原始字节保存
├── .gitignore              构建输出与本地缓存忽略规则
├── src/                    可复现设计源码
│   ├── rtl/                PL 顶层与视频/ROI/评分 RTL（28 个文件）
│   ├── hls/                fitness 网格评分 HLS 核源码与接口说明
│   ├── hardware/           Vivado 工程重建入口、约束与 RTL 副本
│   │   ├── pynq_ax7021b/hardware/
│   │   │   ├── base/       工程创建、XSA 导出与设备树补丁
│   │   │   ├── desktop/    R4 HDMI 彩色直显与叠加
│   │   │   └── qr_desktop/ 二维码采集/ROI/评分系统；roi_selection/rtl 为 src/rtl 的逐文件副本
│   │   ├── qr_mainline_20261015/  参考主线采集工程（ov5640_Ethernet 800x600_48fps）
│   │   └── qr_diag45_20261018/    诊断回放工程
│   ├── software/           PS/Linux 软件与驱动
│   │   ├── src/            ARM 用户态 C 源码（采集、打包、调度、评分后端、主流程）
│   │   ├── include/        用户态与内核共用的头文件
│   │   ├── kernel/         Linux 驱动源码与 Makefile
│   │   ├── camera/         相机控制脚本与 OV5640 720p 配置表
│   │   ├── python/         ax7021b_qr Python 包
│   │   ├── tools/          zynq-qr-data 数据输出工具源码
│   │   ├── imported/       导入的 quirc 解码器、采集与调度源码
│   │   ├── compat/         ARM 构建兼容头文件
│   │   ├── host/           主机端辅助脚本
│   │   └── tests/          主机端 C 测试与兼容性检查
│   ├── platform/
│   │   ├── base_boot/      设备树源（system.dts）与 FIT 配置（image.its）
│   │   └── kernel/         精确内核配置、Module.symvers 与许可证
│   └── vendor/
│       ├── fitness_ip/     已导出的 HLS IP（component.xml、驱动、约束）
│       └── kernel-sdk.json kernel-sdk 分片锁定信息
├── sim/
│   ├── scripts/            Python 验证与 native 多几何回放入口
│   ├── tests/              Python 测试、C 布局测试与 XSim testbench
│   ├── hls_tests/          HLS C 测试（含 legacy 评分）
│   ├── fixtures/           native 回放输入与期望结果
│   └── results/            已记录的 Python / native 验证结果
├── build/
│   ├── scripts/            构建、校验、打包与装配入口（见 3.2）
│   ├── reference/          HLS 收据、时钟约束、设备树与启动打包基准输入
│   ├── reports/            参考综合实现、时序、DRC、CDC 与 HLS 报告
│   ├── MANIFEST.json       源码逐文件 SHA-256 清单
│   ├── DEPENDENCIES.json   基础依赖的固定版本与校验值
│   └── RELEASE.json        版本、工具链与参考固件身份
├── board/                  板端安装与运行控制
│   ├── boot_files.py       安装匹配的启动文件（FSBL/bit/FIT）
│   ├── install.sh          安装运行包并登记服务配置
│   ├── control/            zynq-qr / zynq-qr-camera / zynq-qr-data、相机脚本与 systemd 单元
│   ├── results/            板端接口说明（INTERFACES.md）与参考检查记录
│   ├── serial_console.py   USB-UART 串口终端
│   ├── requirements-host.txt  主机侧串口依赖
│   └── ssh_control.sh      主机侧 SSH 辅助脚本
├── skill/                  13 个可独立复用的工程技能包（见 skill/README.md）
├── data/                   扩展测试数据预留目录
└── report/                 设计报告与过程记录预留目录
```

### 3.1 构建入口 `build/scripts/`

| 脚本 | 用途 |
| --- | --- |
| `verify_release.py` | 校验源码清单（逐文件 SHA-256）、体积上限、RTL 副本一致性、内核配置哈希与 IP 引用完整性 |
| `update_manifest.py` | 有意修改源码或文档后重建 `build/MANIFEST.json` |
| `fetch_dependencies.py` | 下载、校验或离线导入 `kernel-sdk` 与 `platform` 基础依赖 |
| `kernel_sdk_bundle.py` | 校验 kernel-sdk 分片，按需拼回完整归档（`--assemble`） |
| `build_arm.py` | 编译 ARM 用户态库与程序；`--native`/`--host` 为主机端构建 |
| `build_kernel.py` | 用固定 SDK 的内核源码编译驱动模块并检查 vermagic |
| `build_hls.py` | HLS native 参考、C 仿真、综合、IP 导出与 C/RTL 对比 |
| `hardware.py` | 从本地源码与导出 IP 创建并实现 Vivado 工程（不依赖保存的工程） |
| `qualify.py` | 资源、setup/hold、DRC、bus skew 与 CDC 资格检查 |
| `package_boot.py` | 打包启动文件 |
| `r4_package_runtime.py` | 装配板端运行包并校验身份绑定 |
| `stage_board.py` | 校验启动文件与运行包绑定，装配板端安装目录 |
| `r4_rtl_test.py` | 用 Vivado XSim 运行 RTL testbench |

`ac_*.py`、`r4_validate_cdc.py`、`r4_device_tree.py`、`r4_hw_connections.py`、`r4_record_hw.py` 是上述入口的内部步骤，一般不直接调用。

依赖版本、用途及校验详见 [DEPENDENCIES.md](DEPENDENCIES.md)。

## 4. 使用方法

完整流程如下，各步骤可独立执行：

```text
准备环境 → 获取源码与基础依赖 → 本地验证 → 编译 ARM 软件与驱动
        → 重建 PL/HLS 与启动包 → 板端安装 → 运行、采集与校验
```

只做软件验证时，只需第 4.1~4.3 节；重新生成可上板产物需要 AMD 工具链并完成第 4.4~4.6 节。

### 4.1 准备构建环境

完整硬件构建使用 Linux x86-64、Python 3.10 或更新版本、AMD Vivado/Vitis **2025.2**，目标 Cortex-A9 / ARMv7 / NEON / hard-float。参考 ARM 工具链为 AMD GCC 13.4.0。启动文件打包还需要 XSCT、bootgen、dtc、mkimage；RTL 验证使用 XSim。

Ubuntu 通用依赖：

```bash
sudo apt update
sudo apt install git build-essential python3-venv python3-pip binutils \
    device-tree-compiler u-boot-tools libssl-dev libelf-dev
```

AMD 工具需自行安装。设置实际路径：

```bash
export AMD_ROOT="$HOME/tools/2025.2"
export VIVADO_ROOT="$AMD_ROOT/Vivado"
export VITIS_ROOT="$AMD_ROOT/Vitis"
export CC_ARM="$VITIS_ROOT/gnu/aarch32/lin/gcc-arm-linux-gnueabi/bin/arm-linux-gnueabihf-gcc"
export PATH="$VIVADO_ROOT/bin:$VITIS_ROOT/bin:$PATH"
```

Windows 11 的完整构建入口使用 WSL2 Ubuntu 或 Linux 虚拟机，按相同命令操作；不承诺 PowerShell 原生完整构建。

### 4.2 获取源码与基础依赖

```bash
# http
git clone https://github.com/Lone-Jade/ZYNQ7020-QR_Code_Recogition.git

# ssh
git clone git@github.com:Lone-Jade/ZYNQ7020-QR_Code_Recogition.git

cd ZYNQ7020-QR_Code_Recogition
python3 -B build/scripts/verify_release.py

# 下载匹配 Linux 模块 SDK 和平台启动输入，不下载已编译项目交付物：
python3 -B build/scripts/fetch_dependencies.py
python3 -B build/scripts/verify_release.py --dependencies
```

依赖固定在同一仓库的 [source-deps-v1 Release](https://github.com/Lone-Jade/ZYNQ7020-QR_Code_Recogition/releases/tag/source-deps-v1)。公开仓库可以直接下载；私有仓库需先安装 GitHub CLI 并执行 `gh auth login`，使用拥有本仓库读取权限的账户。脚本校验每个文件的大小及 SHA-256，缓存位于被 Git 忽略的 `build/deps/`；不会安装到系统或连接板卡。

只做 PS/Native/RTL 验证无需下载 SDK。只编译驱动时使用 `--group kernel-sdk`；只准备启动文件输入时使用 `--group platform`。已有原始依赖时可按 DEPENDENCIES.md 离线导入。

### 4.3 本地验证（不需要 AMD 工具链）

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r sim/requirements.txt
.venv/bin/python -B sim/scripts/test_python.py
python3 -B build/scripts/build_arm.py --native --label native
.venv/bin/python -B sim/scripts/native_multi_geometry.py
python3 -B build/scripts/r4_rtl_test.py   # 需要 Vivado XSim
```

Python 验证覆盖 PS/显示状态、过期与乱序、目标关联、相机 AEC/AGC 配置、依赖损坏拒绝和重建运行包身份绑定。Native 验证用实际 quirc 解码器检查双码及同内容双码的载荷/四角对应。XSim 验证分流、背压、源身份及场景原子提交。已记录的验证结果见 `sim/results/` 与 `build/reports/source-submission.json`；这些验证不替代实际运动场景的光学测试与整机测量。

### 4.4 编译 ARM 软件与驱动

```bash
python3 -B build/scripts/build_arm.py --label arm
python3 -B build/scripts/build_kernel.py --label modules
```

产物位于 `build/work/arm/` 和 `build/work/kernel/modules/`。驱动使用固定 SDK 中的 Linux 源码和 prepared build tree，模块版本为：

```text
6.12.40-xilinx-ax7021b-pynq-hdmi-g5c57b943fc68
```

脚本检查 ARM ELF 架构、ABI 与模块 vermagic。需要重做时选用新的 `--label`，避免覆盖现有输出。`src/platform/kernel/` 同时保留精确的内核配置和 `Module.symvers`，供审查和校验；它们不能单独代替完整模块编译环境。

### 4.5 重建 PL、HLS 与启动文件

用保留的导出 HLS IP 创建工程并完整综合实现：

```bash
python3 -B build/scripts/hardware.py rebuild1
python3 -B build/scripts/qualify.py rebuild1
```

如只检查工程重建入口，可执行 `python3 -B build/scripts/hardware.py createcheck --create-only`，但这不会进行综合实现。

综合实现输出位于 `build/work/rebuild1/`。`qualify.py` 检查资源、setup/hold、DRC、bus skew 及 CDC；首次检查会要求审查完整 CDC 报告。审查 JSON 必须与本次 routed DCP 的 SHA-256 匹配，不能直接使用参考设计的审查结论：

```bash
python3 -B build/scripts/qualify.py rebuild1 --cdc-review /path/to/cdc-review.json
python3 -B build/scripts/package_boot.py rebuild1
python3 -B build/scripts/r4_package_runtime.py --arm-label arm --kernel-label modules \
    --firmware build/outputs/boot-rebuild1 --output build/outputs/runtime-rebuild1
python3 -B build/scripts/stage_board.py \
    --firmware build/outputs/boot-rebuild1 --runtime build/outputs/runtime-rebuild1 \
    --output build/outputs/board-rebuild1
```

`stage_board.py` 校验启动文件与运行包的绑定，再装配安装目录；不生成压缩包、不部署、不启动板卡。重建的运行包具有自己的 SHA-256，安装器会将相机控制程序绑定到本次经校验的运行包。

需要重新生成 HLS 核时：

```bash
python3 -B build/scripts/build_hls.py --stage all
python3 -B build/scripts/hardware.py rebuildhls \
    --fitness-ip-dir build/work/hls/component/hls/impl/ip \
    --fitness-receipt build/reports/generated/hls/result.json
```

新硬件必须重新做资格检查及上板验证后再部署。基础依赖中的 U-Boot 和 zImage 是与现有 PYNQ 系统匹配的平台输入；本仓库不声称从零构建整套 Linux 发行版或 SD 卡镜像。

### 4.6 板端安装

板端需要已有匹配的 PYNQ/Linux 根文件系统、NumPy 环境和 SD 启动布局。完整 rootfs 与分区镜像不包含在源码或依赖 Release 中。

以下步骤会更新板端启动文件和安装运行包，应只在完成构建与审查后手动执行。替换示例用户和地址：

```bash
# 主机：复制上一步装配的目录
scp -r build/outputs/board-rebuild1 xilinx@192.168.1.11:~/zynq-qr-board
ssh xilinx@192.168.1.11
# 板端：安装匹配启动文件与模块，然后重启
cd ~/zynq-qr-board
sudo python3 -B boot_files.py install
sudo reboot
# 重连板端后
cd ~/zynq-qr-board
sudo sh install.sh
sudo zynq-qr start
sudo zynq-qr status
sudo zynq-qr logs
sudo zynq-qr stop
```

安装工具输出原文件备份位置，保留该位置以便恢复；安装结束保持停止。若安装器返回 `reboot_required: true`，先重启再启动。启动方式为手动命令；关闭 SSH 不会停止服务，重启板卡后需再次执行 `start`。

### 4.7 运行、相机与数据输出

在完成安装的板端执行：

```bash
sudo zynq-qr start
sudo zynq-qr-camera status
sudo zynq-qr-camera auto --max-exposure-ms 3 --max-gain 6
sudo zynq-qr-camera restore
sudo zynq-qr-data --enable
sudo zynq-qr-data
# Ctrl+C退出输出；取消本次事件输出配置：
sudo zynq-qr-data --disable
```

默认 AEC/AGC 上限为 4 ms、8 倍。手动固定可用 `sudo zynq-qr-camera apply --exposure-ms 4 --gain 4`。覆盖配置和事件输出开关在重启后失效。调整配置会短暂停止相机与识别，再恢复之前状态。状态展示配置及初始化回读，不能读取逐帧实际曝光/增益；运动模糊改善和识别率需光学板测。

### 4.8 串口控制台与 HDMI

串口参数为 **115200、8N1、关闭软/硬流控**：

```bash
.venv/bin/python -m pip install -r board/requirements-host.txt
.venv/bin/python board/serial_console.py --port /dev/ttyUSB0
# Windows可用：py -3 board/serial_console.py --port COM5
```

HDMI 是视频输出；命令行登录使用 SSH 或 USB-UART。

## 5. 校验与验证边界

`build/MANIFEST.json` 校验源码内容；`build/DEPENDENCIES.json` 固定基础依赖；`build/RELEASE.json` 记录来源及参考固件身份，不要求参考二进制存在；`build/reports/source-submission.json` 记录本次源码拆分验证范围。修改源码或文档后，先运行 `python3 -B build/scripts/update_manifest.py` 重建清单，再用 `verify_release.py` 复核。

源码版本标签为 `source-v1.0`，精简前的来源提交记录在 `build/RELEASE.json` 的 `source_origin_commit` 字段；最终提交号可用 `git rev-parse HEAD` 查询。

`build/reports/` 中的参考资源、时序、DRC、CDC、HLS 报告保留原始结果，并不代表每次源码构建都重新通过。参考设计有继承的 CDC 诊断和外部 I/O 时序提示，须结合完整报告审查。源码精简验证不等于新的完整综合实现或上板验证。

## 6. 文档索引

| 文档 | 内容 |
| --- | --- |
| [DEPENDENCIES.md](DEPENDENCIES.md) | 基础依赖清单、下载、离线导入与精简范围 |
| [skill/README.md](skill/README.md) | 13 个可独立复用的工程技能包及其使用方式 |
| [board/results/INTERFACES.md](board/results/INTERFACES.md) | PS/PL 运行接口与显示 ABI |
| [src/hls/README.md](src/hls/README.md) | fitness 评分 HLS 核的接口、操作与状态码 |
| [src/platform/kernel/README.md](src/platform/kernel/README.md) | 内核配置与 `Module.symvers` 的来源与校验 |
| [src/hardware/pynq_ax7021b/hardware/qr_desktop/README.md](src/hardware/pynq_ax7021b/hardware/qr_desktop/README.md) | AX7021B 二维码视频硬件源文件 |
| [src/hardware/pynq_ax7021b/hardware/desktop/README.md](src/hardware/pynq_ax7021b/hardware/desktop/README.md) | R4 HDMI 直显与叠加源文件 |

## 7. 许可证

本仓库以 [MIT License](LICENSE) 发布，Copyright (c) 2026 Lone-Jade。

第三方与派生组件保留各自许可证，不因本仓库的 MIT 声明而改变：

- `src/platform/kernel/` 中的 Linux 内核配置、`Module.symvers` 与许可证副本随 kernel-sdk 提供，遵循 GPL-2.0 等原始条款；内核模块按与内核兼容的方式使用其接口。
- `src/software/imported/quirc/` 为 Daniel Beer 的 quirc 解码库，按其文件头部的 ISC 式许可使用。
- `src/vendor/fitness_ip/` 为 AMD 工具导出的 IP，其组件声明与附带文件以目录内说明为准。

分发或再发布前，请以各文件头部的版权与许可声明为准逐项核对。
