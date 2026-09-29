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
```

`inspect` 检查 EFI 目录树，`write_payload` 把 payload 写入镜像后重新挂载读取，`verify_image` 修改 FAT 副本并输出稳定的校验问题码。

## 测试和持续集成

白盒测试覆盖布局阈值、引导扇区、FAT12/16/32 表项、目录项、长文件名、文件读写、目录操作、删除、挂载范围和 verify。CI 对 `wasm-gc`、`wasm`、`js`、`native` 四个目标依次执行：

1. 检查 `moonc` 版本；
2. `moon check`；
3. `moon build --release`；
4. `moon test`；
5. 在 `wasm-gc` 目标运行三个示例。

工作流文件： [.github/workflows/ci.yml](../.github/workflows/ci.yml)。

## MoonCakes

包已发布到 MoonCakes：`chenliyi-cly/moonfat`，版本 `0.1.0`。发布前使用 `moon publish --dry-run` 验证打包结果，正式发布使用同一包名和版本。
