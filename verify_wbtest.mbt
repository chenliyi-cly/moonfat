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
