///|
fn vol_ascii(text : String) -> Bytes {
  Bytes::makei(text.length(), i => text[i].to_int().to_byte())
}

///|
fn vol_fat12_options() -> FormatOptions {
  {
    kind: Fat12,
    bytes_per_sector: 512,
    total_sectors: 160,
    volume_label: "MOONFAT",
    volume_id: 0x4D4F4F4E,
  }
}

///|
fn vol_fat12() -> Volume {
  format_volume(vol_fat12_options()).unwrap()
}

///|
fn vol_has_name(entries : Array[Entry], name : String) -> Bool {
  for i = 0; i < entries.length(); i = i + 1 {
    if entries[i].name == name {
      return true
    }
  }
  false
}

///|
test "format_volume writes boot signature and volume label" {
  let vol = vol_fat12()
  assert_eq(vol.kind(), Fat12)
  assert_eq(vol.label(), "MOONFAT")
  assert_true(vol.cluster_count() > 0)
  assert_eq(vol.data[510], b'\x55')
  assert_eq(vol.data[511], b'\xAA')
  let entries = vol.list("/").unwrap()
  assert_false(vol_has_name(entries, "MOONFAT"))
  assert_eq(entries.length(), 0)
  let issues = vol.verify()
  assert_eq(issues.length(), 0)
}

///|
test "mount roundtrip keeps geometry" {
  let vol = vol_fat12()
  let mounted = mount_bytes(vol.to_bytes()).unwrap()
  assert_eq(mounted.kind(), Fat12)
  assert_eq(mounted.label(), "MOONFAT")
  assert_eq(mounted.cluster_count(), vol.cluster_count())
}

///|
test "mkdir write read and list on FAT12" {
  let vol = vol_fat12()
  vol.mkdir("/EFI").unwrap()
  vol.mkdir("/EFI/BOOT").unwrap()
  vol.write_file("/EFI/BOOT/BOOTX64.EFI", vol_ascii("payload")).unwrap()
  vol.write_file("/README.TXT", vol_ascii("hello")).unwrap()
  let root = vol.list("/").unwrap()
  assert_true(vol_has_name(root, "EFI"))
  assert_true(vol_has_name(root, "README.TXT"))
  assert_false(vol_has_name(root, "."))
  assert_false(vol_has_name(root, ".."))
  let readme = vol.read_file("/README.TXT").unwrap()
  assert_eq(hex_encode(readme), hex_encode(vol_ascii("hello")))
  let payload = vol.read_file("/EFI/BOOT/BOOTX64.EFI").unwrap()
  assert_eq(hex_encode(payload), hex_encode(vol_ascii("payload")))
  let boot = vol.stat("/EFI/BOOT").unwrap()
  assert_true(boot.is_dir)
  let file = vol.stat("/README.TXT").unwrap()
  assert_false(file.is_dir)
  assert_eq(file.size, 5)
}

///|
test "dotdot of a first-level directory stores cluster 0" {
  let vol = vol_fat12()
  vol.mkdir("/EFI").unwrap()
  let entry = vol.stat("/EFI").unwrap()
  let records = read_directory(vol.data, vol.layout, entry.cluster).unwrap()
  match find_record(records, "..") {
    None => fail("missing ..")
    Some(dotdot) => assert_eq(dotdot.cluster, 0)
  }
  match find_record(records, ".") {
    None => fail("missing .")
    Some(dot) => assert_eq(dot.cluster, entry.cluster)
  }
}

///|
test "mkdir missing parent is NotFound" {
  let vol = vol_fat12()
  match vol.mkdir("/NOPE/X") {
    Err(NotFound(_)) => ()
    _ => fail("expected NotFound")
  }
}

///|
test "create_dir_item rejects dots" {
  let vol = vol_fat12()
  match create_dir_item(vol.data, vol.layout, 0, ".", ATTR_DIRECTORY, 2, 0) {
    Err(InvalidName(_)) => ()
    _ => fail("expected InvalidName")
  }
  match create_dir_item(vol.data, vol.layout, 0, "..", ATTR_DIRECTORY, 2, 0) {
    Err(InvalidName(_)) => ()
    _ => fail("expected InvalidName")
  }
}

///|
test "LFN long names roundtrip through list and read" {
  let vol = vol_fat12()
  vol.write_file("/long file name.txt", vol_ascii("lfn-ok")).unwrap()
  let entries = vol.list("/").unwrap()
  assert_true(vol_has_name(entries, "long file name.txt"))
  let got = vol.read_file("/long file name.txt").unwrap()
  assert_eq(hex_encode(got), hex_encode(vol_ascii("lfn-ok")))
}

///|
test "overwrite, empty file, remove and walk" {
  let vol = vol_fat12()
  vol.mkdir_p("/A/B").unwrap()
  vol.write_file("/A/B/C.TXT", vol_ascii("one")).unwrap()
  vol.write_file("/A/B/C.TXT", vol_ascii("two-two")).unwrap()
  assert_eq(
    hex_encode(vol.read_file("/A/B/C.TXT").unwrap()),
    hex_encode(vol_ascii("two-two")),
  )
  vol.write_file("/A/EMPTY.TXT", vol_ascii("")).unwrap()
  assert_eq(vol.read_file("/A/EMPTY.TXT").unwrap().length(), 0)
  match vol.remove("/A/B") {
    Err(DirectoryNotEmpty(_)) => ()
    _ => fail("expected DirectoryNotEmpty")
  }
  vol.remove("/A/B/C.TXT").unwrap()
  vol.remove("/A/B").unwrap()
  match vol.stat("/A/B") {
    Err(NotFound(_)) => ()
    _ => fail("expected NotFound")
  }
  let walked = vol.walk("/").unwrap()
  assert_true(vol_has_name(walked, "A"))
  assert_true(vol_has_name(walked, "EMPTY.TXT"))
}

///|
test "write_file missing parent is NotFound" {
  let vol = vol_fat12()
  match vol.write_file("/missing/dir/X.TXT", vol_ascii("x")) {
    Err(NotFound(_)) => ()
    _ => fail("expected NotFound")
  }
}

///|
test "format_floppy is a 1.44 MB FAT12 image" {
  let vol = format_floppy().unwrap()
  assert_eq(vol.kind(), Fat12)
  assert_eq(vol.total_bytes(), 1474560)
  assert_eq(vol.cluster_count(), 2847)
  assert_eq(vol.verify().length(), 0)
}

///|
test "format_fat16_small mounts as FAT16" {
  let vol = format_fat16_small().unwrap()
  assert_eq(vol.kind(), Fat16)
  assert_eq(vol.cluster_count(), 4096)
  vol.write_file("/HI.TXT", vol_ascii("fat16")).unwrap()
  assert_eq(
    hex_encode(vol.read_file("/HI.TXT").unwrap()),
    hex_encode(vol_ascii("fat16")),
  )
  assert_eq(vol.verify().length(), 0)
}
