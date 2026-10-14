///|
fn vfy_volume() -> Volume {
  format_volume({
    kind: Fat12,
    bytes_per_sector: 512,
    total_sectors: 160,
    volume_label: "MOONFAT",
    volume_id: 0x4D4F4F4E,
  }).unwrap()
}

///|
fn vfy_has_code(codes : Array[String], wanted : String) -> Bool {
  for i = 0; i < codes.length(); i = i + 1 {
    if codes[i] == wanted {
      return true
    }
  }
  false
}

///|
test "verify is clean on a freshly formatted volume" {
  let vol = vfy_volume()
  assert_eq(vol.verify().length(), 0)
  assert_eq(vol.issue_codes().length(), 0)
}

///|
test "verify reports FAT copy mismatch" {
  let vol = vfy_volume()
  vol.write_file("/A.TXT", Bytes::makei(3, i => (65 + i).to_byte())).unwrap()
  let off = fat_base(vol.layout, 1) + 8
  vol.data[off] = (vol.data[off].to_int() ^ 0xFF).to_byte()
  let codes = vol.issue_codes()
  assert_true(vfy_has_code(codes, "VFY015"))
}

///|
test "verify reports a corrupted boot signature" {
  let vol = vfy_volume()
  vol.data[510] = b'\x00'
  let codes = vol.issue_codes()
  assert_true(vfy_has_code(codes, "VFY001"))
}

///|
test "free_clusters drops after a write" {
  let vol = vfy_volume()
  let before = vol.free_clusters().unwrap()
  vol
  .write_file("/BLOB.BIN", Bytes::make(vol.bytes_per_cluster() + 8, b'\x5A'))
  .unwrap()
  let after = vol.free_clusters().unwrap()
  assert_true(after < before)
  assert_eq(before - after, 2)
}

///|
test "DosTime packs to 2026-09-01 12:00:00" {
  let time = default_dos_time()
  let date = pack_dos_date(time)
  let clock = pack_dos_time(time)
  let back = unpack_dos_stamp(date, clock)
  assert_eq(back.year, 2026)
  assert_eq(back.month, 9)
  assert_eq(back.day, 1)
  assert_eq(back.hour, 12)
  assert_eq(back.minute, 0)
  assert_eq(back.second, 0)
}

///|
test "verify stops at a self-referencing directory and reports cross-link" {
  let vol = vfy_volume()
  vol.mkdir("/A").unwrap()
  let parent = find_record(
    read_directory(vol.data, vol.layout, 0).unwrap(),
    "A",
  ).unwrap()
  let _ = create_dir_item(
    vol.data,
    vol.layout,
    parent.cluster,
    "LOOP",
    ATTR_DIRECTORY,
    parent.cluster,
    0,
  ).unwrap()
  let codes = vol.issue_codes()
  assert_true(vfy_has_code(codes, "VFY031"))
  assert_true(!vfy_has_code(codes, "VFY040"))
}

///|
test "verify stops at an ancestor cycle and duplicate directory alias" {
  let vol = vfy_volume()
  vol.mkdir_p("/A/B").unwrap()
  let root = read_directory(vol.data, vol.layout, 0).unwrap()
  let a = find_record(root, "A").unwrap()
  let b = find_record(
    read_directory(vol.data, vol.layout, a.cluster).unwrap(),
    "B",
  ).unwrap()
  let _ = create_dir_item(
    vol.data,
    vol.layout,
    b.cluster,
    "ANCESTOR",
    ATTR_DIRECTORY,
    a.cluster,
    0,
  ).unwrap()
  let _ = create_dir_item(
    vol.data,
    vol.layout,
    0,
    "ALIAS",
    ATTR_DIRECTORY,
    a.cluster,
    0,
  ).unwrap()
  assert_true(vfy_has_code(vol.issue_codes(), "VFY031"))
}

///|
test "verify reports a directory with cluster zero" {
  let vol = vfy_volume()
  let _ = create_dir_item(
    vol.data,
    vol.layout,
    0,
    "BROKEN",
    ATTR_DIRECTORY,
    0,
    0,
  ).unwrap()
  assert_true(vfy_has_code(vol.issue_codes(), "VFY026"))
}

///|
test "verify returns a length issue for a boot-only truncated image" {
  let vol = vfy_volume()
  let short = vol.boot_preview().unwrap()
  vol.data = Array::make(short.length(), b'\x00')
  for i = 0; i < short.length(); i = i + 1 {
    vol.data[i] = short[i]
  }
  let issues = vol.verify()
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "VFY001")
}

///|
test "verify still detects actual orphan and shared file chains" {
  let vol = vfy_volume()
  vol.write_file("/A.TXT", Bytes::make(3, b'\x41')).unwrap()
  let a = find_record(read_directory(vol.data, vol.layout, 0).unwrap(), "A.TXT").unwrap()
  let _ = create_dir_item(
    vol.data,
    vol.layout,
    0,
    "ALIAS.TXT",
    ATTR_ARCHIVE,
    a.cluster,
    a.size,
  ).unwrap()
  let orphan = alloc_cluster(vol.data, vol.layout, 2).unwrap()
  assert_true(orphan != a.cluster)
  let codes = vol.issue_codes()
  assert_true(vfy_has_code(codes, "VFY031"))
  assert_true(vfy_has_code(codes, "VFY040"))
}

///|
test "verify stops before indexing when data no longer matches mounted geometry" {
  let vol = format_floppy().unwrap()
  vol.data = vfy_volume().data
  let issues = vol.verify()
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].code, "VFY002")
}
