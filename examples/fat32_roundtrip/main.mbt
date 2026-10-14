///|
fn main raise {
  let vol = @fat.format_fat32_min().unwrap()
  let empty_issues = vol.verify()
  assert_eq(empty_issues.length(), 0)
  println("empty FAT32: \{empty_issues.length()} issues")
  vol.mkdir_p("/EFI/BOOT").unwrap()
  let payload = Bytes::make(vol.bytes_per_cluster() + 17, b'\x5A')
  vol.write_file("/EFI/BOOT/BOOTX64.EFI", payload).unwrap()
  assert_eq(vol.verify().length(), 0)
  let reopened = @fat.mount_bytes(vol.to_bytes()).unwrap()
  assert_eq(reopened.read_file("/EFI/BOOT/BOOTX64.EFI").unwrap(), payload)
  let reopened_issues = reopened.verify()
  assert_eq(reopened_issues.length(), 0)
  println(
    "remount FAT32: \{reopened_issues.length()} issues, payload \{payload.length()} bytes",
  )
}
