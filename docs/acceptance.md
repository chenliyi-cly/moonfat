# MoonFat 验收指南

这份清单对应项目当前交付状态，验收时可以按下面的路径复现。

## 工具链

项目使用 MoonBit 实现。CI 安装官方 MoonBit 工具链，并检查 `moonc` 版本不低于 `0.10.14`。本地准备好对应版本后，在仓库根目录执行：

```text
moon version --all
moon check --target wasm-gc
moon build --target wasm-gc --release
moon test --target wasm-gc
```

## 仓库和版本

- GitHub 仓库公开可访问：<https://github.com/chenliyi-cly/moonfat>
- 默认分支为 `main`，提交按功能分阶段组织。
- 包名为 `chenliyi-cly/moonfat`，版本在 `moon.mod` 中维护。
- 许可证为 MIT，第三方参考和许可证记录见 `NOTICE`、`THIRD_PARTY.md` 与 `THIRD_PARTY/rust-fatfs.MIT`。

## 核心功能复现

MoonFat 对内存中的 FAT12、FAT16、FAT32 卷执行格式化和挂载，支持引导扇区、FSInfo、双 FAT、8.3/LFN 目录、文件簇链、目录操作，以及只读一致性检查。最小调用和边界说明见 [README.md](../README.md)。

三个示例不依赖外部磁盘：

```text
moon run examples/inspect
moon run examples/write_payload
moon run examples/verify_image
moon run examples/fat32_roundtrip
```

`inspect` 检查 EFI 目录树，`write_payload` 把 payload 写入镜像后重新挂载读取，`verify_image` 修改 FAT 副本并输出稳定的校验问题码。

## 测试和持续集成

白盒测试覆盖布局阈值、引导扇区、FAT12/16/32 表项、目录项、长文件名、文件读写、目录操作、删除、挂载范围和 verify。CI 对 `wasm-gc`、`wasm`、`js`、`native` 四个目标依次执行：

1. 检查 `moonc` 版本；
2. `moon check`；
3. `moon build --release`；
4. `moon test`；
5. 在每个目标运行三个原有示例和 FAT32 格式化、写入、重挂载示例。

工作流文件： [.github/workflows/ci.yml](../.github/workflows/ci.yml)。

## FAT32 回归怎么验

执行 `moon test --filter '*FAT32*'`。测试实际分配完整 FAT32 镜像，覆盖空卷与重新挂载、跨簇文件写入、根目录扩容、非 2 号根簇、真实丢失簇、损坏根链，以及文件引用根簇的交叉链接。`moon run examples/fat32_roundtrip` 给出可独立运行的复现入口，空卷和写入后重挂载都应输出 0 条问题，文件字节必须与输入一致。

另外注入目录自环、祖先循环、目录别名、起始簇为 0 的目录和截断镜像，确认校验能返回问题码。真实的丢失簇、交叉链接和 FAT 副本差异仍应被检出。根目录扩容测试在校验前后比较整卷字节，确认它保持只读。

## MoonCakes

本轮 FAT32 校验修复对应版本 `0.1.2`。可用 `moon add chenliyi-cly/moonfat@0.1.2` 安装，再运行 FAT32 重新挂载示例复验。
