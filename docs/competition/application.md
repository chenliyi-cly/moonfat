# MoonFat 项目申报书

## 基本信息

- 项目名称：MoonFat
- 参赛者：陈李奕
- 联系方式：3534429035@qq.com
- GitHub 仓库链接：https://github.com/chenliyi-cly/moonfat
- 项目方向：基础设施类-库移植
- 是否为移植项目：是（对照 rust-fatfs 的卷模型和读写接口，按 Microsoft FAT 规范用 MoonBit 重写）

## 项目简介

查 U 盘镜像、组 UEFI ESP、给固件做 FAT 包装时，需要在内存里解开 BPB、FAT 表和目录项。MoonBit 里能找到 VFS 抽象和 Win32 常量，没有现成的 FAT12/16/32 编解码。MoonFat 把整卷放进 Array[Byte]，format、mount、列目录、读写、mkdir、只读 verify 走同一套几何，wasm-gc 也能跑。三个示例分别做 ESP 目录检查、payload 打包、以及 FAT 副本被改坏之后的 verify。本机 33 个测试覆盖 1.44MB 软盘几何、小 FAT16 卷，还有 FAT32 表项的高 4 位保留。

### 预期使用场景

1. 固件同学 mount 一份 ESP 镜像，list/walk 看 /EFI/BOOT 里有没有 BOOTX64.EFI。
2. 打包脚本把 payload 写进小 FAT 卷，再把整卷字节交给烧录器。
3. 镜像被改过后跑 verify，用 VFY001、VFY015 定位启动签名和 FAT 副本问题。

## 核心功能范围

- format_volume、format_floppy、format_fat16_small、format_fat32_min
- mount、list、stat、read_file、write_file、mkdir、remove、walk
- FAT12 12-bit 打包、FAT16 16-bit、FAT32 28-bit（写入保留高 4 位）
- 8.3 / LFN、双 FAT、只读 verify
- 技术路径与关键理解：簇数 <4085 用 FAT12，<65525 用 FAT16，否则 FAT32；BPB 以 0x55AA 结尾；FAT32 带 FSInfo 和备份引导扇；目录项 32 字节
- 明确不做：exFAT、FUSE、GPT/MBR 解析、自动修复写入
- MoonCakes 检索词与结论：fat、fat12、fat16、fat32、vfat、fatfs、exfat。本地 2694 条包索引和 mooncakes.io/api-new/v0/modules 无同名编解码。相邻 mizchi/vfs 是存储后端，win32.mbt 只暴露分区常量

## 移植或参考说明

原项目名称：rust-fatfs。原项目链接：https://github.com/rafalh/rust-fatfs。原项目许可证：MIT（Copyright 2017 Rafal Harabien）。移植范围：卷几何、FAT 表、目录/LFN、format 与读写接口的结构。源码按 MoonBit 0.10.4 重写，测试和三个示例是新的。未支持：exFAT、真实块设备、异步 IO。当前 33 个测试通过，覆盖 1.44MB 软盘、约 2MB FAT16 卷，以及 FAT32 表项打包（默认测试不分配 34MB 镜像）。
