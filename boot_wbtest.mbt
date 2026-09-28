///|
test "cluster count thresholds select FAT kind" {
  assert_eq(fat_kind_from_clusters(4084), Fat12)
  assert_eq(fat_kind_from_clusters(4085), Fat16)
  assert_eq(fat_kind_from_clusters(65524), Fat16)
  assert_eq(fat_kind_from_clusters(65525), Fat32)
  assert_eq(Fat12.name(), "FAT12")
  assert_eq(Fat16.bits(), 16)
  assert_eq(Fat32.eoc_value(), 0x0FFFFFFF)
  assert_eq(Fat12.bad_value(), 0xFF7)
  assert_true(Fat12.is_eoc(0xFF8))
  assert_true(Fat16.is_bad(0xFFF7))
  assert_true(Fat32.is_eoc(0x0FFFFFFF))
  assert_false(Fat32.is_bad(0x0FFFFFF8))
}

///|
test "floppy layout matches 1.44 MB FAT12 geometry" {
  let layout = compute_layout(floppy_1440_options()).unwrap()
  assert_eq(layout.kind, Fat12)
  assert_eq(layout.bytes_per_sector, 512)
  assert_eq(layout.sectors_per_cluster, 1)
  assert_eq(layout.reserved_sectors, 1)
  assert_eq(layout.fat_count, 2)
  assert_eq(layout.fat_sectors, 9)
  assert_eq(layout.root_entries, 224)
  assert_eq(layout.root_dir_sectors, 14)
  assert_eq(layout.first_data_sector, 33)
  assert_eq(layout.cluster_count, 2847)
  assert_eq(layout.total_sectors, 2880)
}

///|
test "small FAT16 layout crosses the 4085 cluster line" {
  let layout = compute_layout(small_fat16_options()).unwrap()
  assert_eq(layout.kind, Fat16)
  assert_eq(layout.reserved_sectors, 1)
  assert_eq(layout.root_entries, 512)
  assert_eq(layout.root_dir_sectors, 32)
  assert_eq(layout.fat_sectors, 17)
  assert_eq(layout.first_data_sector, 67)
  assert_eq(layout.cluster_count, 4096)
}

///|
test "minimum FAT32 layout uses 65525 clusters" {
  let layout = compute_layout(min_fat32_options()).unwrap()
  assert_eq(layout.kind, Fat32)
  assert_eq(layout.reserved_sectors, 32)
  assert_eq(layout.root_entries, 0)
  assert_eq(layout.root_cluster, 2)
  assert_eq(layout.fsinfo_sector, 1)
  assert_eq(layout.backup_boot_sector, 6)
  assert_eq(layout.fat_sectors, 512)
  assert_eq(layout.first_data_sector, 1056)
  assert_eq(layout.cluster_count, 65525)
}

///|
test "parse_layout rejects a truncated boot sector" {
  let data = Array::make(64, b'\x00')
  match parse_layout(data) {
    Err(Truncated(_)) => ()
    _ => fail("expected Truncated")
  }
}

///|
test "parse_layout rejects missing 55AA signature" {
  let data = Array::make(512, b'\x00')
  match parse_layout(data) {
    Err(InvalidBoot(_)) => ()
    _ => fail("expected InvalidBoot")
  }
}
