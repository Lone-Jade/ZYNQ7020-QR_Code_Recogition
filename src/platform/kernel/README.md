# 匹配的内核 ABI 输入

`kernel.config` 和 `Module.symvers` 从锁定的 kernel-sdk 原始归档直接提取，不是从内核版本号推断或重新生成。哈希必须与 `src/vendor/kernel-sdk.json` 一致。源码校验入口会检查这两项。

完整驱动构建仍需要依赖 Release 中的精确 Linux 源码和 prepared build tree；获取方式见根目录 DEPENDENCIES.md。配置和符号表本身不能代替整个 SDK。
