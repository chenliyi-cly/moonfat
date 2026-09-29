# MoonFat

MoonBit 里的 FAT12/16/32 卷编解码。给它一块 `Array[Byte]`，可以 format、mount、列目录、读写文件、建目录、再做只读校验。不接真实磁盘，也不做 FUSE，所以 wasm-gc / wasm / js / native 都能用。

对标 [rust-fatfs](https://github.com/rafalh/rust-fatfs) 的卷模型和读写接口，磁盘布局按 Microsoft FAT 规范：簇数 <4085 用 FAT12，<65525 用 FAT16，否则 FAT32。

## 能做什么

- 写引导扇、FSInfo、双 FAT、静态根目录或 FAT32 根簇
- 12-bit / 16-bit / 28-bit FAT 表项（FAT32 写入时保留高 4 位）
- 8.3 短名和 LFN，`~` 数字尾
- `list` / `stat` / `read_file` / `write_file` / `mkdir` / `remove` / `walk`
- 只读 `verify`，给出 VFY001、VFY015 这类稳定码

## 明确不做

不管 exFAT，不挂 FUSE，不解析 GPT/MBR，也不把损坏的 FAT 写回去。默认测试不算 34MB 的最小 FAT32 镜像，只测表项打包和 `compute_layout`。

## 安装

要求 MoonBit `moonc >= 0.10.14`。建议使用官方安装器，再确认版本：

```text
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
moon version --all
```

安装项目包：

```text
moon add chenliyi-cly/moonfat
```

也可以直接 clone 本仓库当源码依赖。

## 三个可跑示例

```text
moon run examples/inspect
moon run examples/write_payload
moon run examples/verify_image
```

### 1. 检查 USB / EFI 目录树

- 谁：拿着 ESP 或 U 盘镜像的固件同学
- 输入：内存里的 FAT 字节
- 结果：看到 `/EFI/BOOT/BOOTX64.EFI` 在不在、多大

`inspect` 先 format 一个 80KB 的小 FAT12 卷，建 `EFI/BOOT`，写入假的 `BOOTX64.EFI`，再 `list` / `walk`。

### 2. 打包固件 payload

- 谁：要把固件文件塞进 FAT 镜像再送给烧录器的脚本
- 输入：payload 字节和卷参数
- 结果：得到整卷 `Bytes`，重 mount 后能读回原文件

`write_payload` 把 `firmware-payload-v1` 写到 `/payload/app.bin`，打印 hex 和镜像大小。

### 3. 损坏后做校验

- 谁：镜像被改过、想先看坏在哪的人
- 输入：一份本来干净的卷，再人工改 FAT 副本
- 结果：`verify` 给出 `VFY015`（两份 FAT 对不上）

`verify_image` 先确认干净卷 0 条 issue，再对 FAT 副本 1 做 xor。

## 最短调用

```moonbit
let vol = format_volume({
  kind: Fat12,
  bytes_per_sector: 512,
  total_sectors: 160,
  volume_label: "MOONFAT",
  volume_id: 0x4D4F4F4E,
}).unwrap()
vol.mkdir("/EFI").unwrap()
vol.write_file("/README.TXT", payload).unwrap()
let names = vol.list("/").unwrap()
let issues = vol.verify()
```

1.44MB 软盘和最小 FAT16 卷也有现成入口：`format_floppy`、`format_fat16_small`。`format_fat32_min` 会得到约 34MB 的镜像，适合显式调用，不要放进默认 CI。

## 校验

完整验收步骤见 [docs/acceptance.md](docs/acceptance.md)。CI 在 Ubuntu 上使用 `moonc >= 0.10.14` 检查、构建、测试 `wasm-gc`、`wasm`、`js` 和 `native`，并在 `wasm-gc` 上运行三个示例。

本地可按实际安装的工具链执行：

```text
moon check --target wasm-gc
moon build --target wasm-gc --release
moon test --target wasm-gc
moon run examples/inspect
moon run examples/write_payload
moon run examples/verify_image
```

## 许可证

MIT。卷布局参考 Microsoft FAT 规范和 rust-fatfs（MIT）。详见 `NOTICE` 和 `THIRD_PARTY.md`。
