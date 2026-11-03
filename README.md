# 高速智能仓储二维码识别系统

本项目是`全国大学生嵌入式芯片与系统设计竞赛——FPGA创新设计赛道——AMD初级赛道`作品。

## 1. 项目简介

> 随着智能仓储与物流向自动化、高速化发展，货物出入库及分拣对二维码读取的实时性、准确性与稳定性提出更高要求。传统工业相机结合CPU工控机的视觉方案在连续高速处理时面临计算负载、设备成本与功耗等挑战。
>
> 本项目基于Zynq-7020/AX7021B，设计面向仓储场景的二维码识别与硬件加速系统。依托PS-PL协同架构，PL完成摄像头采集、灰度处理、候选区域提取、透视网格评分加速及彩色预览与标注叠加；PS/Linux负责系统控制、任务调度、定位后端、最终采样、纠错解码及结果管理。通过流水线评分、整网格作业与独立显示通路提高并行处理效率，减少软硬件交互及ARM显示开销，并利用帧身份校验与缓冲管理保障数据一致性。软硬件一体化设计减少对独立高性能工控机的依赖，具有降低部署成本和运行功耗的潜力。
>
> 最终构建了面向仓储物流场景的嵌入式视觉识别系统。2026年10月27日的传送带网页仿真测试测试中，最终版在5000个目标中识别4997个，识别率99.94%，按采样时长加权的处理帧率为27.94 FPS；纯PS版在1000个目标中识别909个。2026年11月3日另开展了实际K4～K6纸片的真实传送带测试，结果及连续测试分组的时间误差单独列于第5节，不与网页测试合并统计。

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
- 网页仿真测试：最终版 4997/5000，识别率 99.94%，加权处理帧率 27.94 FPS；纯 PS 版 909/1000，识别率 90.90%，加权处理帧率 3.07 FPS
- 真实传送带测试：实际 K4 独立组为 50/50；实际 K5、K6 在指定的估算时间分界下各为 50/50。K6 对时间分界敏感，须结合第 5.2 节的误差说明解读

## 3. 仓库结构

本仓库的 `main` 是源码复现版本，最终提交仓库地址始终是 [https://github.com/Lone-Jade/ZYNQ7020-QR_Code_Recogition](https://github.com/Lone-Jade/ZYNQ7020-QR_Code_Recogition)。

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
├── data/                   网页最终版5000次、纯PS1000次及真实传送带K4～K6测试CSV与校验记录
└── report/                 设计报告与过程记录预留目录
```

### 3.1 构建入口 `build/scripts/`

| 脚本                      | 用途                                                                                   |
| ------------------------- | -------------------------------------------------------------------------------------- |
| `verify_release.py`     | 校验源码清单（逐文件 SHA-256）、体积上限、RTL 副本一致性、内核配置哈希与 IP 引用完整性 |
| `update_manifest.py`    | 有意修改源码或文档后重建 `build/MANIFEST.json`                                       |
| `fetch_dependencies.py` | 下载、校验或离线导入 `kernel-sdk` 与 `platform` 基础依赖                           |
| `kernel_sdk_bundle.py`  | 校验 kernel-sdk 分片，按需拼回完整归档（`--assemble`）                               |
| `build_arm.py`          | 编译 ARM 用户态库与程序；`--native`/`--host` 为主机端构建                          |
| `build_kernel.py`       | 用固定 SDK 的内核源码编译驱动模块并检查 vermagic                                       |
| `build_hls.py`          | HLS native 参考、C 仿真、综合、IP 导出与 C/RTL 对比                                    |
| `hardware.py`           | 从本地源码与导出 IP 创建并实现 Vivado 工程（不依赖保存的工程）                         |
| `qualify.py`            | 资源、setup/hold、DRC、bus skew 与 CDC 资格检查                                        |
| `package_boot.py`       | 打包启动文件                                                                           |
| `r4_package_runtime.py` | 装配板端运行包并校验身份绑定                                                           |
| `stage_board.py`        | 校验启动文件与运行包绑定，装配板端安装目录                                             |
| `r4_rtl_test.py`        | 用 Vivado XSim 运行 RTL testbench                                                      |

`ac_*.py`、`r4_validate_cdc.py`、`r4_device_tree.py`、`r4_hw_connections.py`、`r4_record_hw.py` 是上述入口的内部步骤，一般不直接调用。

依赖版本、用途及校验详见 [DEPENDENCIES.md](DEPENDENCIES.md)。

## 4. 使用方法

本节按“准备主机 → 获取源码和依赖 → 准备板上 Linux、编译软件与驱动 → 构建 PL/HLS 和启动固件 → 板端安装 → 检查输出”的顺序说明。除明确标为“板端”的命令外，均在 **Ubuntu 22.04 LTS x86-64 主机的 Bash 终端**执行；进入仓库后，后续主机命令均以仓库根目录为工作目录。

### 4.1 环境准备

整体使用两套操作系统：开发主机为 **Ubuntu 22.04 LTS x86-64**（本项目源码复现验证主机为 22.04.5）；AX7021B 板端为 **ARM32 PYNQ/Linux**，原系统基于 Ubuntu 22.04 Jammy 根文件系统和 PYNQ 3.1.1 适配。板端最终运行的定制内核必须与本仓库驱动一致，版本见第 4.3 节。

| 项目          | 要求                                                                                                            |
| ------------- | --------------------------------------------------------------------------------------------------------------- |
| 硬件          | AX7021B / XC7Z020CLG484-2、项目使用的摄像头、HDMI 显示器、带匹配系统的 SD 卡、电源与网线；USB-UART 用于启动排查 |
| PL / HLS 工具 | AMD Vivado、Vitis 2025.2；RTL 仿真使用 Vivado XSim，HLS 重建使用 Vitis HLS                                      |
| 主机 Python   | Python 3.10 或更新版本；使用独立虚拟环境安装验证与串口依赖                                                      |
| ARM 编译器    | Cortex-A9 / ARMv7 / NEON / hard-float；参考工具链为 AMD GCC 13.4.0                                              |
| 启动打包工具  | XSCT、bootgen、dtc、mkimage、GNU binutils                                                                       |
| 板端运行环境  | systemd、SSH、Python 3、NumPy；项目运行解释器为 `/usr/local/share/pynq-venv/bin/python`                       |

先安装 Ubuntu 通用依赖：

```bash
sudo apt update
sudo apt install git build-essential python3-venv python3-pip binutils \
    device-tree-compiler u-boot-tools libssl-dev libelf-dev openssh-client
```

AMD 工具需另行安装。以下路径仅为示例，请改为实际安装目录，并在每个新开的构建终端中设置：

```bash
export AMD_ROOT="$HOME/tools/2025.2"
export VIVADO_ROOT="$AMD_ROOT/Vivado"
export VITIS_ROOT="$AMD_ROOT/Vitis"
export CC_ARM="$VITIS_ROOT/gnu/aarch32/lin/gcc-arm-linux-gnueabi/bin/arm-linux-gnueabihf-gcc"
export PATH="$VIVADO_ROOT/bin:$VITIS_ROOT/bin:$PATH"

python3 --version
vivado -version
"$CC_ARM" --version
command -v xsct bootgen dtc mkimage
```

应能找到上述工具，Vivado 应显示 2025.2。Windows 11 用户可在 WSL2 Ubuntu 或 Linux 虚拟机中按本节 Linux 流程操作；本仓库未验证 PowerShell 原生完整构建。HDMI 是板端视频输出，命令行登录使用 SSH 或 USB-UART。

### 4.2 克隆仓库和安装依赖

以下使用 HTTPS 克隆；如果已配置 SSH 密钥，可改用注释中的 SSH 命令，**两种方式任选一种**：

```bash
git clone https://github.com/Lone-Jade/ZYNQ7020-QR_Code_Recogition.git
# git clone git@github.com:Lone-Jade/ZYNQ7020-QR_Code_Recogition.git
cd ZYNQ7020-QR_Code_Recogition

python3 -B build/scripts/verify_release.py
python3 -m venv .venv
.venv/bin/python -m pip install -r sim/requirements.txt -r board/requirements-host.txt

python3 -B build/scripts/fetch_dependencies.py
python3 -B build/scripts/verify_release.py --dependencies
```

固定基础依赖来自同一仓库的 [source-deps-v1 Release](https://github.com/Lone-Jade/ZYNQ7020-QR_Code_Recogition/releases/tag/source-deps-v1)，共 335,002,276 字节，解包和构建还需数 GiB 以上工作空间。脚本按 `build/DEPENDENCIES.json` 核对大小和 SHA-256，缓存到 `build/deps/`。仓库为私有时，需先安装 GitHub CLI，并用有读取权限的账户执行 `gh auth login`；公开仓库可直接下载。分组下载和离线导入方法见 [DEPENDENCIES.md](DEPENDENCIES.md)。

只做 Python / Native 软件验证时，可以跳过基础依赖下载与 AMD 工具安装，执行：

```bash
.venv/bin/python -B sim/scripts/test_python.py
python3 -B build/scripts/build_arm.py --native --label native
.venv/bin/python -B sim/scripts/native_multi_geometry.py
```

这些检查覆盖状态管理、相机配置和 quirc 解码器的多目标载荷/四角对应；已有结果见 `sim/results/`。RTL 仿真另见第 4.4 节，需要 XSim。

### 4.3 板上 Linux 系统准备与构建

**先准备可启动的 AX7021B PYNQ/Linux 系统，再重建本项目的软件、驱动和启动固件。** 当前 `source-deps-v1` Release 的内容如下（2026-11-02 核对）：

| Release 附件                             | 用途                                                             |
| ---------------------------------------- | ---------------------------------------------------------------- |
| `kernel-sdk.tar.gz.part01`～`part08` | 匹配内核的源码、配置和已准备的模块编译环境，用于重建三个项目驱动 |
| `u-boot.elf`                           | 启动文件打包使用的 U-Boot 输入                                   |
| `zImage`                               | 已编译的匹配 Linux 内核，后续封装进 `image.ub`                 |
| `boot.scr`                             | SD 卡启动脚本                                                    |

上述附件**不包含完整 SD 卡镜像或 PYNQ 根文件系统**，不能直接写入空白 SD 卡启动。已有匹配系统时，可沿用根文件系统和分区布局，再按本节与第 4.4、4.5 节更新驱动、启动文件和应用。使用空白卡时，还需取得匹配 AX7021B 的完整系统镜像，或根文件系统、板级配置与系统构建输入；这些输入目前没有在本仓库 Release 中提供，因此本仓库当前不能独立完成“空白 SD 卡到完整 PYNQ 系统”的构建。

原系统使用 SD 卡启动分区和持久化 Linux 根文件系统，启动关系为：

```text
BOOT.BIN（FSBL + PL 位流 + U-Boot + 设备树）
    → boot.scr → image.ub（Linux 内核 + 设备树）→ SD 卡根文件系统
```

板端应能通过 SSH 或串口登录，启动分区挂载到 `/boot`，运行解释器应能导入 NumPy。可在现有板端检查：

```bash
# 板端执行
uname -m
findmnt /
findmnt /boot
/usr/local/share/pynq-venv/bin/python -c 'import numpy; print(numpy.__version__)'
```

CPU 架构应为 `armv7l`。不要直接套用其他 PYNQ 板卡的镜像；从零适配可参考 [PYNQ 3.1 系统构建指南](https://pynq.readthedocs.io/en/v3.1/pynq_sd_card.html)，但仍需 AX7021B 板级定义和本项目 2025.2 工具链适配，不能把通用 rootfs 当作完整板卡镜像。

回到主机仓库根目录，编译 ARM 用户态软件与三个内核驱动：

```bash
python3 -B build/scripts/build_arm.py --label arm
python3 -B build/scripts/build_kernel.py --label modules
```

| 输出目录                                         | 内容                                                                                |
| ------------------------------------------------ | ----------------------------------------------------------------------------------- |
| `build/work/arm/`                              | ARM 用户态程序、库与编译校验记录                                                    |
| `build/work/kernel/modules/module/`            | `ax7021b_qr_capture.ko`、`ax7021b_qr_fitness.ko`、`ax7021b_camera_display.ko` |
| `build/work/kernel/modules/build_receipt.json` | 驱动源码、模块哈希与内核版本校验记录                                                |

驱动使用固定 SDK 编译，脚本检查 ARM ELF 架构、ABI 与模块 vermagic。最终内核版本必须为：

```text
6.12.40-xilinx-ax7021b-pynq-hdmi-g5c57b943fc68
```

这里的 `build_kernel.py` 编译项目驱动；内核本体使用 Release 中已锁定的 `zImage`。第 4.4 节会生成新的 FSBL、设备树及启动文件，第 4.5 节安装并重启后，再用 `uname -r` 核对最终版本。`src/platform/kernel/` 中的配置与 `Module.symvers` 用于审查和校验，不能单独代替完整 SDK 或根文件系统。

### 4.4 Vivado 工程构建与 HLS IP 生成

默认流程使用仓库中已导出的 HLS IP，从 RTL、Tcl、约束和本地 IP 重新创建 Vivado 工程并完成综合、实现与 XSA 导出：

```bash
python3 -B build/scripts/hardware.py rebuild1
```

生成的工程为 `build/work/rebuild1/ax7021b_linux_qr_desktop/ax7021b_linux_qr_desktop.xpr`，可用 Vivado 2025.2 打开查看；包含位流的 XSA 位于 `build/work/rebuild1/output/ax7021b_linux_qr_desktop.xsa`。只检查工程创建而不综合实现时，可单独执行 `python3 -B build/scripts/hardware.py createcheck --create-only`。

如果修改了 HLS 源码，或希望从 HLS 源码重新生成 IP，改用以下分支：

```bash
python3 -B build/scripts/build_hls.py --stage all
python3 -B build/scripts/hardware.py rebuildhls \
    --fitness-ip-dir build/work/hls/component/hls/impl/ip \
    --fitness-receipt build/reports/generated/hls/result.json
```

HLS 流程包含 C 仿真、综合、IP 导出和 C/RTL 对比。选择此分支后，下文所有 `rebuild1` 均替换为 `rebuildhls`，包括输出目录名，保证使用同一次硬件构建的产物。重做构建时使用新的 `--label` 或硬件构建标签，避免覆盖已有目录。

运行 RTL 仿真和新硬件资格检查：

```bash
python3 -B build/scripts/r4_rtl_test.py
python3 -B build/scripts/qualify.py rebuild1
```

资格检查覆盖资源、setup/hold、DRC、bus skew 与 CDC。自动检查通过但尚未提交人工 CDC 审查时，脚本会提示 `Bounds passed; inspect the full CDC diagnostics...` 并退出；这是要求补齐审查，不能当作完整通过。其他报错应先排查。

审查本次 `build/work/rebuild1-cdc/full-cdc.txt` 等完整报告，并计算本次 routed DCP 的哈希：

```bash
sha256sum build/work/rebuild1/ax7021b_linux_qr_desktop/ax7021b_linux_qr_desktop.runs/impl_1/qr_desktop_top_routed.dcp
```

审查通过后创建自己的 JSON，例如 `build/work/rebuild1/cdc-review.json`，其中 `passed` 为 `true`、`reference_sha256` 为上述实际 SHA-256，并记录审查依据。必须先完成真实审查，不能直接复制参考设计结论。随后执行：

```bash
python3 -B build/scripts/qualify.py rebuild1 \
    --cdc-review build/work/rebuild1/cdc-review.json
python3 -B build/scripts/package_boot.py rebuild1
python3 -B build/scripts/r4_package_runtime.py --arm-label arm --kernel-label modules \
    --firmware build/outputs/boot-rebuild1 --output build/outputs/runtime-rebuild1
python3 -B build/scripts/stage_board.py \
    --firmware build/outputs/boot-rebuild1 --runtime build/outputs/runtime-rebuild1 \
    --output build/outputs/board-rebuild1
```

启动包位于 `build/outputs/boot-rebuild1/`；板端安装目录位于 `build/outputs/board-rebuild1/`，含启动文件、驱动、运行包与安装工具。装配脚本检查固件和运行包的身份绑定，只生成目录，不生成压缩包、不连接板卡。修改 PL/HLS 后需重新完成资格检查和实际板测。

### 4.5 板端安装和使用

先连接摄像头、HDMI、网线并启动现有板端系统。下例的 `xilinx` 和 `192.168.1.11` 均为占位值，请改为实际账户与地址；复制目标目录应尚不存在，重复安装时换一个新目录名。

```bash
# 主机执行
scp -r build/outputs/board-rebuild1 xilinx@192.168.1.11:~/zynq-qr-board
ssh xilinx@192.168.1.11
```

以下在板端执行。安装工具会备份被替换的文件并输出备份位置，请保留该位置用于恢复：

```bash
# 板端：安装匹配启动文件和驱动，再重启
cd ~/zynq-qr-board
sudo python3 -B boot_files.py install
sudo reboot
```

等待板卡重启后，从主机重新 SSH 登录，再在板端执行：

```bash
cd ~/zynq-qr-board
uname -r
sudo sh install.sh
sudo zynq-qr status
```

`uname -r` 应与第 4.3 节完全一致。安装完成保持停止；若安装器返回 `reboot_required: true`，先重启再启动。正常使用命令如下：

```bash
sudo zynq-qr start
sudo zynq-qr status
sudo zynq-qr logs
# 结束识别时执行
sudo zynq-qr stop
```

启动后关闭 SSH 不会停止识别；重启板卡后需要再次手动执行 `start`。每次正常启动默认启用自动曝光 AEC 和自动增益 AGC，上限为 4 ms、8 倍。可按需调整：

```bash
sudo zynq-qr-camera status
sudo zynq-qr-camera auto --max-exposure-ms 3 --max-gain 6
# 或使用固定曝光与增益
sudo zynq-qr-camera apply --exposure-ms 4 --gain 4
# 恢复默认自动配置
sudo zynq-qr-camera restore
```

调整配置会短暂停止相机与识别，再恢复之前状态；覆盖配置在板卡重启后失效。`status` 展示配置和初始化回读，不能读取逐帧实际曝光/增益。

需要在终端查看解码载荷时：

```bash
sudo zynq-qr-data --enable
sudo zynq-qr-data
# Ctrl+C 退出查看；取消本次事件输出配置
sudo zynq-qr-data --disable
```

启用事件输出时，若识别正在运行，会重启识别进程以应用配置；该配置在板卡重启后失效。SSH 不可用时，可在主机使用 USB-UART 控制台：

```bash
.venv/bin/python board/serial_console.py --port /dev/ttyUSB0
# Windows 串口终端示例：py -3 board/serial_console.py --port COM5
```

串口参数为 **115200、8N1、关闭软/硬流控**。

### 4.6 预期输出效果

| 检查项                         | 预期现象                                                                                      |
| ------------------------------ | --------------------------------------------------------------------------------------------- |
| HDMI 画面                      | 摄像头 1280×720 彩色预览；输入约 30 FPS，HDMI 输出时序为 60 Hz                               |
| 识别叠加                       | 成功解码的目标显示绿色框和最多 9 个 ASCII 字符的标签                                          |
| `sudo zynq-qr status`        | 正常启动后 `state` 为 `running`，`artifact_integrity` 为 `true`；停止后为 `stopped` |
| `sudo zynq-qr-camera status` | 显示 AEC/AGC 或固定配置及初始化回读                                                           |
| `sudo zynq-qr-data`          | 启用后跟随新的解码事件，每行输出完整载荷文本；同一发布事件去重，控制字符转义                  |
| 日志                           | `sudo zynq-qr logs` 可查看服务启动与识别日志，用于定位相机、驱动或运行包问题                |

例如，将内容为 `WAREHOUSE-001` 的二维码放入摄像头视野，正常解码后 HDMI 对应位置出现绿色框及长度受限的标签；终端数据输出应包含完整的 `WAREHOUSE-001`。HDMI 标签长度与终端完整载荷长度不同。

启动后可短暂处于 `starting`；若长期未进入 `running`、完整性检查未通过或画面异常，结合状态、日志与串口输出排查。第 2.3 节的识别率和吞吐量为项目指定测试场景的测量结果，复现时需在实际光照、距离、运动速度和二维码尺寸条件下重新测量；主机仿真或成功打包不能替代板端整机验收。

## 5. 测试结果与数据文件

提交数据位于 [`data/`](data/)，包括 24 个 UTF-8 BOM 编码的 CSV 和 1 个真实传送带导出校验 JSON。网页仿真测试和真实传送带分别统计；不同尺寸、不同版本中的同编号纸码不合并为一个目标。

### 5.1 网页仿真测试：最终版与纯 PS

测试日期为 **2026-10-27**。原虚拟传送带生成器经显示器全屏播放，再由摄像头拍摄识别。

| 版本与范围          | 有效组数 | 展示目标数 | 成功 | 漏检 | 识别率 | 加权处理 FPS |
| ------------------- | -------: | ---------: | ---: | ---: | -----: | -----------: |
| 最终版（PS+PL）累计 |       50 |       5000 | 4997 |    3 | 99.94% |       27.939 |
| 纯 PS 版            |       10 |       1000 |  909 |   91 | 90.90% |        3.074 |

最终版累计包含原有 1000 次和后续追加 4000 次，每组 100 个目标；纯 PS 保留原有 1000 次，没有追加到 5000 次。场景为源画布 1280×760、源 K4～K6、固定双车道、密度 6、旋转角度 −180°～180°，无额外模糊或污损。生成器速度取 6.0、4.8、3.6、2.4、1.8，单位为生成器单位，源画布像素速度为速度值乘 135，不能换算为本次实物传送带速度。

相同输入序列的对照限于最终版原有 1000 次与纯 PS 的 1000 次：分别成功 999、909 个，识别率为 99.90%、90.90%；加权处理帧率为 28.070、3.074 FPS，比值约 9.13。两版本分别经摄像头采集，已核对完整 payload、尺寸、角度、车道和形状一致；它们不是同一批相机像素帧。该帧率比值描述本次运行条件下的处理表现，不代表纯计算核最大加速比。

### 5.2 真实传送带：实际 K4～K6

测试日期为 **2026-11-03**。三种尺寸各 50 张二维码纸片，编号均为 1～50，组内顺序不限。完整内容沿用原虚拟传送带场景网页的编号规则。尺寸名称已按实物更正：**原称 K3→实际 K4，原称 K4→实际 K5，原称 K5→实际 K6**；CSV 的 `k` 为更正后的实际标签，`recorded_k` 保留更正前的名称。K 在此是纸片尺寸标签，不是实测相机像素/模块。

| 实际尺寸 | 成功/展示 |  识别率 | 记录方式                                             |
| -------- | --------: | ------: | ---------------------------------------------------- |
| K4       |     50/50 | 100.00% | 独立分组，原始日志已封存                             |
| K5       |     50/50 | 100.00% | 连续日志恢复后，按指定时间的估算分界统计             |
| K6       |     50/50 | 100.00% | 连续日志恢复后，按指定时间的估算分界统计；对分界敏感 |

K5、K6 连续测试的指定切换时间为 **北京时间 2026-11-03 20:56:10**：估算时间不晚于该时刻的解码记录归 K5，晚于该时刻的归 K6。板卡随后关机/重启，恢复时从上次启动的持久 journal 中取回 3338 条记录，核对了原启动编号、识别进程 PID 和相机 source epoch。

**连续两组的分界存在时间误差。**旧启动未保存精确时钟同步，板卡墙钟也与电脑不同；因此使用开始快照的板端单调时间与电脑接收时间估算。开始请求至接收的锚点窗口约 **15.805 秒**，时钟漂移和人为切换误差未另行测量。上表的 K5、K6 结果属于指定估算分界下的结果，不能视为精确分时验证。

将分界在上述锚点窗口内移动，K5 的成功目标数仍为 50，K6 为 **42～50**。K6 的 **11、14、20、24、39、44、47、50 号**对分界敏感，逐目标的 `boundary_sensitive` 字段和分界敏感性表已保留这些差异；这个范围仅描述所分析的锚点窗口，不覆盖未测量的全部误差。

测试采用自动曝光 AEC、自动增益 AGC，配置曝光上限 4 ms、增益上限 8 倍，启动前寄存器读回通过；这些是配置与初始化读回，不能作为每帧实际曝光/增益。此前输入错误和相机诊断中断的尝试均排除。真实传送带速度未测量，没有用网页速度替代。

真实测试的处理帧率保留于 CSV。K5、K6 的值来自各估算时间段内的 worker progress 样本，可能包含等待和结束过码至关机前的尾段；关机前没有取得最终实时服务快照，因此不将它们作为独立、受控的吞吐量对比。

### 5.3 数据索引

| 数据文件                                                                                                                                                                                             | 内容                                       |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| [test_summary.csv](data/test_summary.csv)                                                                                                                                                             | 网页最终版 5000 次与纯 PS 1000 次总览      |
| [final_5000_groups.csv](data/final_5000_groups.csv)、[final_5000_targets.csv](data/final_5000_targets.csv)                                                                                             | 最终版 50 组、5000 条目标明细              |
| [final_5000_by_speed.csv](data/final_5000_by_speed.csv)、[final_5000_by_speed_k.csv](data/final_5000_by_speed_k.csv)                                                                                   | 最终版按生成器速度及源 K 分档              |
| [pure_ps_1000_groups.csv](data/pure_ps_1000_groups.csv)、[pure_ps_1000_targets.csv](data/pure_ps_1000_targets.csv)                                                                                     | 纯 PS 10 组、1000 条目标明细               |
| [pure_ps_1000_by_speed.csv](data/pure_ps_1000_by_speed.csv)、[pure_ps_1000_by_speed_k.csv](data/pure_ps_1000_by_speed_k.csv)                                                                           | 纯 PS 按生成器速度及源 K 分档              |
| [paired_1000_comparison.csv](data/paired_1000_comparison.csv)、[missed_targets.csv](data/missed_targets.csv)                                                                                           | 网页原有 1000 次同序列对照及两版本漏检清单 |
| [physical_summary.csv](data/physical_summary.csv)、[physical_targets.csv](data/physical_targets.csv)                                                                                                   | 实际 K4～K6 汇总和 150 条目标结果          |
| [physical_K4_targets.csv](data/physical_K4_targets.csv)、[physical_K5_targets.csv](data/physical_K5_targets.csv)、[physical_K6_targets.csv](data/physical_K6_targets.csv)                               | 三种实际尺寸各 50 条明细                   |
| [physical_continuous_decode_events.csv](data/physical_continuous_decode_events.csv)                                                                                                                   | 恢复的连续测试逐解码记录、估算时间和归组   |
| [physical_boundary_sensitivity.csv](data/physical_boundary_sensitivity.csv)、[physical_label_corrections.csv](data/physical_label_corrections.csv)                                                     | 分界敏感性与尺寸标签更正映射               |
| [measurement_notes.csv](data/measurement_notes.csv)、[data_dictionary.csv](data/data_dictionary.csv)、[source_manifest.csv](data/source_manifest.csv)                                                   | 网页测试口径、字段含义和来源哈希           |
| [physical_measurement_notes.csv](data/physical_measurement_notes.csv)、[physical_source_manifest.csv](data/physical_source_manifest.csv)、[physical_export_audit.json](data/physical_export_audit.json) | 真实测试口径、恢复来源及导出文件校验       |

### 5.4 计数与验证口径

- 识别成功按组内完整 payload 匹配。`recognized=1` 表示该目标至少解码成功一次；重复解码仅增加 `decode_observations`，不增加成功目标数。
- 识别率以确认展示的目标数为分母；`unexpected_unique` 单列不属于该组真值的额外内容。当前导出的三类测试中均为 0。
- 处理 FPS 来自 worker 累计帧数与采样时间之差，汇总时按采样时长加权，包含运行等待；它不等于 HDMI 刷新率、预览帧率或网页渲染帧率，本次没有测量端到端延迟。
- 真实连续测试的 `time_is_estimate=1`、`boundary_sensitive` 和 `recognized_min_over_anchor_window` / `recognized_max_over_anchor_window` 用于保留分界不确定性，不应在引用结果时省略。
- 原始运行目录保留采集时的历史名称。来源清单用于定位和核对归档，提交 CSV 的实际尺寸标签以 `k` 为准，不按原目录名反推。

## 6. 校验与验证边界

`build/MANIFEST.json` 校验源码内容；`build/DEPENDENCIES.json` 固定基础依赖；`build/RELEASE.json` 记录来源及参考固件身份，不要求参考二进制存在；`build/reports/source-submission.json` 记录本次源码拆分验证范围。修改源码或文档后，先运行 `python3 -B build/scripts/update_manifest.py` 重建清单，再用 `verify_release.py` 复核。

源码版本标签为 `source-v1.0`，精简前的来源提交记录在 `build/RELEASE.json` 的 `source_origin_commit` 字段；最终提交号可用 `git rev-parse HEAD` 查询。

`build/reports/` 中的参考资源、时序、DRC、CDC、HLS 报告保留原始结果，并不代表每次源码构建都重新通过。参考设计有继承的 CDC 诊断和外部 I/O 时序提示，须结合完整报告审查。源码精简验证不等于新的完整综合实现或上板验证。

## 7. 文档索引

| 文档                                                                                                              | 内容                                            |
| ----------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| [data/test_summary.csv](data/test_summary.csv)                                                                     | 网页最终版 5000 次与纯 PS 1000 次汇总           |
| [data/physical_summary.csv](data/physical_summary.csv)                                                             | 真实 K4～K6 汇总，须结合第 5.2 节和时间误差说明 |
| [DEPENDENCIES.md](DEPENDENCIES.md)                                                                                 | 基础依赖清单、下载、离线导入与精简范围          |
| [skill/README.md](skill/README.md)                                                                                 | 13 个可独立复用的工程技能包及其使用方式         |
| [board/results/INTERFACES.md](board/results/INTERFACES.md)                                                         | PS/PL 运行接口与显示 ABI                        |
| [src/hls/README.md](src/hls/README.md)                                                                             | fitness 评分 HLS 核的接口、操作与状态码         |
| [src/platform/kernel/README.md](src/platform/kernel/README.md)                                                     | 内核配置与 `Module.symvers` 的来源与校验      |
| [src/hardware/pynq_ax7021b/hardware/qr_desktop/README.md](src/hardware/pynq_ax7021b/hardware/qr_desktop/README.md) | AX7021B 二维码视频硬件源文件                    |
| [src/hardware/pynq_ax7021b/hardware/desktop/README.md](src/hardware/pynq_ax7021b/hardware/desktop/README.md)       | R4 HDMI 直显与叠加源文件                        |

## 8. 许可证

本仓库以 [MIT License](LICENSE) 发布，Copyright (c) 2026 Lone-Jade。

第三方与派生组件保留各自许可证，不因本仓库的 MIT 声明而改变：

- `src/platform/kernel/` 中的 Linux 内核配置、`Module.symvers` 与许可证副本随 kernel-sdk 提供，遵循 GPL-2.0 等原始条款；内核模块按与内核兼容的方式使用其接口。
- `src/software/imported/quirc/` 为 Daniel Beer 的 quirc 解码库，按其文件头部的 ISC 式许可使用。
- `src/vendor/fitness_ip/` 为 AMD 工具导出的 IP，其组件声明与附带文件以目录内说明为准。

分发或再发布前，请以各文件头部的版权与许可声明为准逐项核对。
