///|
test "FatError codes stay stable" {
  assert_eq(Truncated("boot", 512, 16).code(), "FAT001")
  assert_eq(InvalidBoot("sig").code(), "FAT002")
  assert_eq(Unsupported("exfat").code(), "FAT003")
  assert_eq(BadCluster(7).code(), "FAT004")
  assert_eq(ChainLoop(4).code(), "FAT005")
  assert_eq(NotFound("/nope").code(), "FAT006")
  assert_eq(AlreadyExists("/a").code(), "FAT007")
  assert_eq(NotDirectory("/f").code(), "FAT008")
  assert_eq(IsDirectory("/d").code(), "FAT009")
  assert_eq(DirectoryNotEmpty("/d").code(), "FAT010")
  assert_eq(NoSpace.code(), "FAT011")
  assert_eq(InvalidName(".").code(), "FAT012")
  assert_eq(Corrupt("chain").code(), "FAT013")
  assert_eq(InvalidPath("").code(), "FAT014")
  assert_eq(SlotExhausted.code(), "FAT015")
}

///|
test "FatError render includes code and message" {
  let err = Truncated("boot", 512, 16)
  assert_eq(err.render(), "FAT001: truncated boot: need 512 bytes, have 16")
}
