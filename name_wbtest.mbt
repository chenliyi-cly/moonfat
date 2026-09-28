///|
test "split_path accepts slash and backslash" {
  let a = split_path("/EFI/BOOT/BOOTX64.EFI").unwrap()
  assert_eq(a.length(), 3)
  assert_eq(a[0], "EFI")
  assert_eq(a[1], "BOOT")
  assert_eq(a[2], "BOOTX64.EFI")
  let b = split_path("EFI\\BOOT").unwrap()
  assert_eq(b.length(), 2)
  assert_eq(b[0], "EFI")
  assert_eq(b[1], "BOOT")
}

///|
test "split_path rejects empty path" {
  match split_path("") {
    Err(InvalidPath(_)) => ()
    _ => fail("expected InvalidPath")
  }
}

///|
test "needs_lfn for case, spaces and extra dots" {
  assert_false(needs_lfn("README.TXT"))
  assert_true(needs_lfn("readme.txt"))
  assert_true(needs_lfn("long file name.txt"))
  assert_true(needs_lfn("FILE.TAR.GZ"))
  assert_false(needs_lfn("BOOTX64.EFI"))
}

///|
test "short name packing and LFN checksum" {
  let short = pack_short_name("README", "TXT")
  assert_eq(display_short_name(short), "README.TXT")
  assert_eq(lfn_checksum(short), 0x73)
  let plain = allocate_short_name("README.TXT", []).unwrap()
  assert_eq(display_short_name(plain), "README.TXT")
  let long = allocate_short_name("Firmware Payload.bin", []).unwrap()
  assert_eq(display_short_name(long), "FIRMWA~1.BIN")
  let collide = allocate_short_name("Firmware Payload.bin", [long]).unwrap()
  assert_eq(display_short_name(collide), "FIRMWA~2.BIN")
}

///|
test "utf16 roundtrip for BMP names" {
  let units = utf16_units("EFI")
  assert_eq(units.length(), 3)
  assert_eq(string_from_utf16(units), "EFI")
}
