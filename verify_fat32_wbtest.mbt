///|
test "FAT32 empty volume and remount have no lost root cluster" {
  let vol = format_fat32_min().unwrap()
  assert_eq(vol.kind(), Fat32)
  assert_eq(vol.verify().length(), 0)
  let reopened = mount_bytes(vol.to_bytes()).unwrap()
  assert_eq(reopened.verify().length(), 0)
}

///|
test "FAT32 write and remount keep the root reachable" {
  let vol = format_fat32_min().unwrap()
  vol.mkdir_p("/EFI/BOOT").unwrap()
  let payload = Bytes::make(vol.bytes_per_cluster() + 17, b'\x5A')
  vol.write_file("/EFI/BOOT/BOOTX64.EFI", payload).unwrap()
  assert_eq(vol.verify().length(), 0)
  let reopened = mount_bytes(vol.to_bytes()).unwrap()
  assert_eq(reopened.read_file("/EFI/BOOT/BOOTX64.EFI").unwrap(), payload)
  assert_eq(reopened.verify().length(), 0)
}

///|
test "FAT32 expanded root marks all clusters and verify does not mutate bytes" {
  let vol = format_fat32_min().unwrap()
  for i = 0; i < 20; i = i + 1 {
    vol.write_file("/F\{i}.TXT", Bytes::make(1, b'\x42')).unwrap()
  }
  let chain = follow_chain(vol.data, vol.layout, vol.layout.root_cluster).unwrap()
  assert_true(chain.length() > 1)
  let before = vol.to_bytes()
  assert_eq(vol.verify().length(), 0)
  assert_eq(vol.to_bytes(), before)
  let reopened = mount_bytes(before).unwrap()
  assert_eq(reopened.list("/").unwrap().length(), 20)
  assert_eq(reopened.verify().length(), 0)
}

///|
test "FAT32 a relocated root is reachable but orphan allocations are not" {
  let vol = format_fat32_min().unwrap()
  let old_offset = vol.layout.cluster_sector(2).unwrap() * 512
  let new_offset = vol.layout.cluster_sector(5).unwrap() * 512
  for i = 0; i < vol.bytes_per_cluster(); i = i + 1 {
    vol.data[new_offset + i] = vol.data[old_offset + i]
    vol.data[old_offset + i] = b'\x00'
  }
  write_fat_entry(vol.data, vol.layout, 2, 0).unwrap()
  write_fat_entry(vol.data, vol.layout, 5, vol.layout.kind.eoc_value()).unwrap()
  put_u32le(vol.data, 44, 5).unwrap()
  put_u32le(vol.data, vol.layout.backup_boot_sector * 512 + 44, 5).unwrap()
  let relocated = mount_bytes(vol.to_bytes()).unwrap()
  assert_eq(relocated.layout.root_cluster, 5)
  assert_eq(relocated.verify().length(), 0)
  write_fat_entry(
    relocated.data,
    relocated.layout,
    8,
    relocated.kind().eoc_value(),
  ).unwrap()
  let issues = relocated.verify()
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "VFY040")
  assert_eq(
    issues[0].message,
    "1 allocated clusters are not reachable from directories",
  )
}

///|
test "FAT32 corrupt root chains are reported instead of accepted" {
  let vol = format_fat32_min().unwrap()
  write_fat_entry(vol.data, vol.layout, 2, 3).unwrap()
  write_fat_entry(vol.data, vol.layout, 3, 2).unwrap()
  assert_true(vfy_has_code(vol.issue_codes(), "VFY020"))
  write_fat_entry(vol.data, vol.layout, 2, 0).unwrap()
  assert_true(vfy_has_code(vol.issue_codes(), "VFY020"))
}

///|
test "FAT32 file referencing root reports a cross-link without losing root" {
  let vol = format_fat32_min().unwrap()
  vol.write_file("/BAD.TXT", Bytes::make(1, b'\x41')).unwrap()
  let record = find_record(
    read_directory(vol.data, vol.layout, 2).unwrap(),
    "BAD.TXT",
  ).unwrap()
  write_fat_entry(vol.data, vol.layout, record.cluster, 0).unwrap()
  put_u16le(vol.data, record.short_offset + 26, 2).unwrap()
  let codes = vol.issue_codes()
  assert_true(vfy_has_code(codes, "VFY031"))
  assert_true(!vfy_has_code(codes, "VFY040"))
}

///|
test "FAT32 directory pointing to root terminates with cross-link" {
  let vol = format_fat32_min().unwrap()
  let _ = create_dir_item(vol.data, vol.layout, 2, "LOOP", ATTR_DIRECTORY, 2, 0).unwrap()
  let before = vol.to_bytes()
  let codes = vol.issue_codes()
  assert_true(vfy_has_code(codes, "VFY031"))
  assert_true(!vfy_has_code(codes, "VFY040"))
  assert_eq(vol.to_bytes(), before)
}

///|
test "FAT32 root outside the data region is invalid" {
  let vol = format_fat32_min().unwrap()
  put_u32le(vol.data, 44, vol.cluster_count() + 2).unwrap()
  let reopened = mount_bytes(vol.to_bytes()).unwrap()
  let codes = reopened.issue_codes()
  assert_true(vfy_has_code(codes, "VFY003"))
  assert_true(vfy_has_code(codes, "VFY020"))
}
