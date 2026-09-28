# Third-party

- Microsoft FAT specification (FAT12/FAT16/FAT32 on-disk layout). Used for BPB fields, cluster-count thresholds (<4085 FAT12, <65525 FAT16, otherwise FAT32), 32-byte directory entries, LFN checksum, and FAT32 reserved high nibble.
- rust-fatfs, MIT, Copyright 2017 Rafal Harabien. https://github.com/rafalh/rust-fatfs
  Informed volume geometry, dual FAT copies, directory/LFN handling, and the format/read/write API shape. License text: `THIRD_PARTY/rust-fatfs.MIT`.

This repository does not contain rust-fatfs source files. The MoonBit code, tests, and examples were written for this project.
