///|
fn table_fat12_layout() -> Layout {
  {
    kind: Fat12,
    bytes_per_sector: 512,
    sectors_per_cluster: 1,
    reserved_sectors: 1,
    fat_count: 2,
    fat_sectors: 1,
    root_entries: 16,
    root_dir_sectors: 1,
    first_fat_sector: 1,
    first_root_sector: 3,
    first_data_sector: 4,
    cluster_count: 16,
    root_cluster: 0,
    total_sectors: 24,
    media: b'\xF0',
    volume_id: 1,
    label: "TINY12",
    fsinfo_sector: 0,
    backup_boot_sector: 0,
  }
}

///|
fn table_fat32_layout() -> Layout {
  {
    kind: Fat32,
    bytes_per_sector: 512,
    sectors_per_cluster: 1,
    reserved_sectors: 1,
    fat_count: 2,
    fat_sectors: 1,
    root_entries: 0,
    root_dir_sectors: 0,
    first_fat_sector: 1,
    first_root_sector: 3,
    first_data_sector: 3,
    cluster_count: 16,
    root_cluster: 2,
    total_sectors: 20,
    media: b'\xF8',
    volume_id: 1,
    label: "TINY32",
    fsinfo_sector: 0,
    backup_boot_sector: 0,
  }
}

///|
test "FAT12 odd and even entries pack into 12-bit slots" {
  let layout = table_fat12_layout()
  let data = Array::make(
    layout.total_sectors * layout.bytes_per_sector,
    b'\x00',
  )
  init_fat_tables(data, layout).unwrap()
  write_fat_entry(data, layout, 2, 0xABC).unwrap()
  write_fat_entry(data, layout, 3, 0x123).unwrap()
  assert_eq(read_fat_raw(data, layout, 2).unwrap(), 0xABC)
  assert_eq(read_fat_raw(data, layout, 3).unwrap(), 0x123)
  let a = fat_base(layout, 0)
  let b = fat_base(layout, 1)
  let mut i = 0
  while i < 16 {
    assert_eq(data[a + i], data[b + i])
    i = i + 1
  }
}

///|
test "FAT12 chain follow and free" {
  let layout = table_fat12_layout()
  let data = Array::make(
    layout.total_sectors * layout.bytes_per_sector,
    b'\x00',
  )
  init_fat_tables(data, layout).unwrap()
  let first = alloc_chain(data, layout, 3, 2).unwrap()
  let chain = follow_chain(data, layout, first).unwrap()
  assert_eq(chain.length(), 3)
  free_chain(data, layout, first).unwrap()
  assert_eq(read_fat_raw(data, layout, chain[0]).unwrap(), 0)
  assert_eq(read_fat_raw(data, layout, chain[1]).unwrap(), 0)
  assert_eq(read_fat_raw(data, layout, chain[2]).unwrap(), 0)
}

///|
test "FAT32 writes keep the reserved high nibble" {
  let layout = table_fat32_layout()
  let data = Array::make(
    layout.total_sectors * layout.bytes_per_sector,
    b'\x00',
  )
  init_fat_tables(data, layout).unwrap()
  let rel = fat_entry_offset(layout, 4).unwrap()
  let base = fat_base(layout, 0)
  put_u8(data, base + rel + 3, 160).unwrap()
  assert_eq(data[base + rel + 3].to_int(), 160)
  write_fat_entry(data, layout, 4, 0x0F123456).unwrap()
  assert_eq(read_fat_raw(data, layout, 4).unwrap(), 0x0F123456)
  assert_eq(data[base + rel + 3].to_int(), 175)
  let copy = fat_base(layout, 1)
  assert_eq(data[copy + rel + 3].to_int(), 15)
}

///|
test "hex_encode lowercases bytes" {
  let bytes = Bytes::from_array([b'\x55', b'\xAA'])
  assert_eq(hex_encode(bytes), "55aa")
}
