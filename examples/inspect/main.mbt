///|
fn ascii(text : String) -> Bytes {
  Bytes::makei(text.length(), i => text[i].to_int().to_byte())
}

///|
fn main {
  let vol = @fat.format_volume({
    kind: @fat.Fat12,
    bytes_per_sector: 512,
    total_sectors: 160,
    volume_label: "ESP",
    volume_id: 0x4D4F4F4E,
  }).unwrap()
  vol.mkdir("/EFI").unwrap()
  vol.mkdir("/EFI/BOOT").unwrap()
  vol.write_file("/EFI/BOOT/BOOTX64.EFI", ascii("fake-efi")).unwrap()
  println(
    "kind=\{vol.kind().name()} label=\{vol.label()} bytes=\{vol.total_bytes()}",
  )
  let root = vol.list("/").unwrap()
  println("root \{root.length()} entries")
  let mut i = 0
  while i < root.length() {
    println("  \{root[i].name}")
    i = i + 1
  }
  let boot = vol.list("/EFI/BOOT").unwrap()
  i = 0
  while i < boot.length() {
    println("EFI/BOOT \{boot[i].name} size=\{boot[i].size}")
    i = i + 1
  }
  let walked = vol.walk("/").unwrap()
  println("walk \{walked.length()} names")
}
