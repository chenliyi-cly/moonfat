# Duplicate check — MoonFat

- Date: 2026-09-28
- Candidate: MoonFat, a FAT12/16/32 on-disk volume codec (boot/BPB, FAT
  tables, directories, LFN, cluster chains, format, read/write, verify).
- Decision: proceed. User affirmed this direction after the moonfbs leftover
  slice was rejected.

## Search terms

fat, fat12, fat16, fat32, exfat, vfat, fatfs, iso9660, joliet, libfdt,
devicetree, filesystem, vfs, fuse, smb

## moon search

Local `moon` on PATH has no `search` subcommand. Evidence used instead:

- Local MoonCakes registry index: C:\Users\42673\.moon\registry\index\user
  (2694 package index files). Keyword hits for fat12/fat16/fat32/exfat/vfat/
  fatfs/iso9660/joliet/libfdt/devicetree/device-tree: 0.
- Live dump https://mooncakes.io/api-new/v0/modules (~2690 modules). Same
  codec keywords empty. Query parameter `q` is ignored by this API.

## osc2026-guide

Skill installed. Project research guide followed via registry grep plus
GitHub `language:MoonBit` repo/code search. No FAT12/16/32 codec package.

## Adjacent projects (not the same capability)

- mizchi/vfs: virtual FS abstraction, backends memory/idb/s3/sqlite/realfs.
- moonbit-community/win32.mbt: generated Win32 constants (PARTITION_FAT32,
  IMAPI ISO9660 names), not an on-disk parser.
- R00TK17/moonbit-HexEditor: ZIP/GZip OS enum 0 => "FAT".
- BigOrangeQWQ/wasi-filesystem: WASI FS API.
- Registry reserved: MoonFuse (FUSE protocol), MoonSMB (SMB2/3 frames).
- sabas0ba/rv32mbt: loads a DTB blob; unrelated to FAT.

## GitHub

`gh search repos --language MoonBit fat32|fat12|iso9660|libfdt|devicetree|fatfs`
returned no dedicated codec repositories. Code hits are Win32 constants and
mimetype `application/x-iso9660-image`.

## Registry

No reserved MoonFat / FAT12 / FAT32 identity. MoonConstruct duplication-gated.
Serialization neighbourhood crowded; not used.

## Overlap judgement

Empty on-disk FAT codec. Distinct from VFS, FUSE, SMB, zip/tar, and Win32
bindings. Scope is the full FAT12/16/32 domain, not a leftover slice. exFAT
is out of scope (patent/license).

## Recheck date

2026-09-28
