# 基础依赖与精简范围

本项目源码与基础平台环境分开提供。匿名提交材料不包含个人仓库地址：

- 优先使用下文的 `--source-dir` 离线导入。在线获取时，设置环境变量 `ZYNQ_QR_DEPENDENCY_REPOSITORY=组织或账号/仓库名`，或填写 `build/DEPENDENCIES.json` 的 `repository`。
- 固定依赖 Release：`source-deps-v1`。
- 机器可读锁定清单：`build/DEPENDENCIES.json`，逐文件记录字节数、SHA-256。

## kernel-sdk

八个原始分片 `kernel-sdk.tar.gz.part01` 至 `part08`，共 319,004,426 字节（304.226 MiB）。这是精简前已校验的精确 Linux 模块 SDK，没有重新压缩或替换版本。完整归档 SHA-256：

```text
bb6f276c2c249efc01e5fa48755faee349c1bd6a7459a36a7aacaf77c6a95ff5
```

内含 Linux 源码快照、prepared build tree、生成头文件和编译所需工具，匹配内核 `6.12.40-xilinx-ax7021b-pynq-hdmi-g5c57b943fc68`。只凭版本字符串不能保证匹配；必须使用锁定的原始文件。`src/platform/kernel/kernel.config` 与 `Module.symvers` 从同一 SDK 提取，并保留独立校验。具体完整源码及其许可证也包含在 SDK 的 kernel-source 中。

```bash
python3 -B build/scripts/fetch_dependencies.py --group kernel-sdk
python3 -B build/scripts/kernel_sdk_bundle.py
python3 -B build/scripts/build_kernel.py --label modules
```

缓存分片位于 `build/deps/kernel-sdk/`；驱动构建在 `build/work/` 校验拼接和解包。SDK 中普通文件未压缩内容约 1.49 GB，需为分片、拼接归档和解包预留足够空间。校验失败不会作为成功下载缓存。

## platform

三个原始平台输入：`u-boot.elf`、`zImage`、`boot.scr`，共 15,997,850 字节（15.257 MiB）。用于在本项目 PL/XSA、FSBL、设备树构建完成后打包启动文件。设备树源文件和 FIT 配置保留在 `src/platform/base_boot/`。

```bash
python3 -B build/scripts/fetch_dependencies.py --group platform
```

缓存位于 `build/deps/platform/`。这些文件是匹配的外部平台二进制输入，不是本项目二维码算法源码，也不构成完整 SD 系统镜像。本仓库没有完整 U-Boot/Linux 发行版从零构建流程；准确复现当前启动打包使用的是这些经校验的输入。

## 认证与离线导入

公开 Release 可以直接下载；私有仓库先安装 GitHub CLI 并执行 `gh auth login`，不要把令牌写进源码、URL 或聊天记录。下载器优先使用已登录的 GitHub CLI，否则使用公开 HTTPS 下载地址。

已有原始依赖时，可以离线导入，每个目录按文件原名存放：

```bash
python3 -B build/scripts/fetch_dependencies.py --group kernel-sdk --source-dir /path/to/sdk-chunks
python3 -B build/scripts/fetch_dependencies.py --group platform --source-dir /path/to/platform-inputs
python3 -B build/scripts/fetch_dependencies.py --check
python3 -B build/scripts/verify_release.py --dependencies
```

没有匹配依赖时，脚本明确报错，不回退到宿主机其他内核或历史工程目录。

## 源码不附带的交付物

Vivado 生成工程、DCP、参考 bit/XSA/FSBL/DTB、已编译 board/boot 和 board/runtime 均从源码树排除。新产物只写入忽略的 `build/work/`、`build/outputs/`。默认保留必要导出 HLS IP及其 receipt，以支持不重跑 HLS 的源码构建路径。

200 MB 检查针对源码内容；完整平台依赖下载总量约 335 MB（十进制）。完整离线依赖合计不满足 200 MB，不能将源码体积与离线完整环境体积混为一谈。
