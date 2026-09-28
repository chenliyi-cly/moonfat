# AI usage

Codex helped write MoonBit modules, whitebox tests, examples, and docs. On-disk numbers come from the Microsoft FAT spec and from rust-fatfs behavior (cluster thresholds, 0x55AA, 12-bit packing, LFN checksum), not from unverified model guesses.

Tests assert concrete values: floppy geometry 2880/224/9, FAT16 4096 clusters, FAT32 65525 clusters, LFN checksum 0x73, FAT32 reserved nibble 0xA0 -> 0xAF. `moon test` and `moon check --deny-warn` were run locally on wasm-gc before the public push.
