# ZYNQ7020 / AX7021B 二维码实时识别

面向智能仓储与传送带场景的二维码识别系统。硬件为 AX7021B（XC7Z020CLG484-2）、OV5640 摄像头及 HDMI 显示器。PL 完成视频采集、RGB565 直显、Gray8 和候选 ROI 生成、fitness 网格评分及绿色框/文字叠加；PS/Linux 完成二维码定位、纠错解码、结果关联和运行控制。

摄像头输入为 1280×720、约 30 FPS，HDMI 输出时序为 60 Hz。解码成功目标显示绿色框及最多 9 个 ASCII 字符的标签。正常启动使用 `sudo zynq-qr start`，每次启动默认启用自动曝光 AEC 和自动增益 AGC，上限为 4 ms、8 倍。

## 竞赛提交与目录

本仓库的 `main` 是源码复现版本。最终提交仓库地址始终是：

```text
git@github.com:Lone-Jade/ZYNQ7020-QR_Code_Recogition.git
```

源码保留 RTL、HLS、PS/Linux 软件、驱动、必要导出 IP、构建脚本、约束、测试和关键验证记录。不包含 Vivado 生成工程、DCP、参考位流/XSA、已编译启动和运行包、Linux SDK 归档或 Git 历史备份。源码内容应低于 200,000,000 字节，校验入口会检查这一限制；基础依赖需额外下载，下载后会占用数 GiB 工作空间。

```text
src/        RTL、HLS、PS 软件、驱动、必要 IP、平台配置和设备树源码
sim/        Python/Native/RTL 验证与最小测试输入
build/      构建脚本、依赖锁定清单、源码清单和参考验证报告
board/      板端安装、恢复、相机与运行控制的源码
skill/      项目技能包
report/     设计报告与大模型协作记录预留目录
data/       扩展测试数据预留目录
```

`src/rtl/` 与硬件工程对应 RTL 逐文件绑定；不要只替换其中一份。`build/reference/hls.json` 和时钟基线仍是构建/资格检查输入；不能整体删除 `build/` 或 `src/vendor/`。

精简前的来源提交为 `d57d272c7ea841812e960de689b3d99bf5a61673`。源码版本标签为 `source-v1.0`；最终提交号可用 `git rev-parse HEAD` 查询。依赖固定在同一仓库的 [source-deps-v1 Release](https://github.com/Lone-Jade/ZYNQ7020-QR_Code_Recogition/releases/tag/source-deps-v1)。依赖版本、用途及校验详见 [DEPENDENCIES.md](DEPENDENCIES.md)。

## 开发环境

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

## 获取源码与基础依赖

```bash
git clone git@github.com:Lone-Jade/ZYNQ7020-QR_Code_Recogition.git ZYNQ7020-QR_code_Recognition
cd ZYNQ7020-QR_code_Recognition
python3 -B build/scripts/verify_release.py

# 下载匹配 Linux 模块 SDK 和平台启动输入，不下载已编译项目交付物：
python3 -B build/scripts/fetch_dependencies.py
python3 -B build/scripts/verify_release.py --dependencies
```

公开仓库可以直接下载；私有仓库需先安装 GitHub CLI 并执行 `gh auth login`，使用拥有本仓库读取权限的账户。脚本校验每个文件的大小及 SHA-256，缓存位于被 Git 忽略的 `build/deps/`。它不会安装到系统或连接板卡。

只做 PS/Native/RTL 验证无需下载 SDK。只编译驱动时使用 `--group kernel-sdk`；只准备启动文件输入时使用 `--group platform`。也可按 DEPENDENCIES.md 从已有的精确依赖文件导入。

## 功能与 RTL 验证

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r sim/requirements.txt
.venv/bin/python -B sim/scripts/test_python.py
python3 -B build/scripts/build_arm.py --native --label native
.venv/bin/python -B sim/scripts/native_multi_geometry.py
python3 -B build/scripts/r4_rtl_test.py
```

Python 验证覆盖 PS/显示状态、过期与乱序、目标关联、相机 AEC/AGC 配置、依赖损坏拒绝和重建运行包身份绑定。Native 验证用实际 quirc 解码器检查双码及同内容双码的载荷/四角对应。XSim 验证分流、背压、源身份及场景原子提交；这些验证不替代实际运动场景光学测试。

## 编译 ARM 软件与驱动

```bash
python3 -B build/scripts/build_arm.py --label arm
python3 -B build/scripts/build_kernel.py --label modules
```

产物位于 `build/work/arm/` 和 `build/work/kernel/modules/`。驱动使用固定 SDK 中的 Linux 源码和 prepared build tree，模块版本为：

```text
6.12.40-xilinx-ax7021b-pynq-hdmi-g5c57b943fc68
```

脚本检查 ARM ELF 架构、ABI 与模块 vermagic。需要重做时选用新的 `--label`，避免覆盖现有输出。`src/platform/kernel/` 同时保留精确的内核配置和 Module.symvers，供审查和校验；它们不能单独代替完整模块编译环境。

## 构建 PL、HLS 与启动文件

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

## 板端安装和运行

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

串口参数为 **115200、8N1、关闭软/硬流控**：

```bash
.venv/bin/python -m pip install -r board/requirements-host.txt
.venv/bin/python board/serial_console.py --port /dev/ttyUSB0
# Windows可用：py -3 board/serial_console.py --port COM5
```

HDMI 是视频输出；命令行登录使用 SSH 或 USB-UART。

## 相机与解码输出

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

## 校验和验证边界

`build/MANIFEST.json` 校验源码内容；`build/DEPENDENCIES.json` 固定基础依赖；`build/RELEASE.json` 记录来源及参考固件身份，不要求参考二进制存在。`build/reports/source-submission.json` 记录本次源码拆分验证范围。

`build/reports/` 中的参考资源、时序、DRC、CDC、HLS 报告保留原始结果，并不代表每次源码构建都重新通过。参考设计有继承的 CDC 诊断和外部 I/O 时序提示，须结合完整报告审查。源码精简验证不等于新的完整综合实现或上板验证。

`data/`、`report/` 预留扩展测试、正式设计报告及大模型协作记录。技能包使用方法见 [skill/README.md](skill/README.md)。
