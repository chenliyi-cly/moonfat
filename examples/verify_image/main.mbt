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
    volume_label: "CHECK",
    volume_id: 0x43484543,
  }).unwrap()
  vol.write_file("/README.TXT", ascii("ok")).unwrap()
  println("clean issues=\{vol.verify().length()}")
  let copy1 = (vol.layout.first_fat_sector + vol.layout.fat_sectors) *
    vol.layout.bytes_per_sector
  vol.data[copy1] = (vol.data[copy1].to_int() ^ 255).to_byte()
  let issues = vol.verify()
  println("after xor issues=\{issues.length()}")
  let mut i = 0
  while i < issues.length() {
    println("\{issues[i].code} \{issues[i].message}")
    i = i + 1
  }
}
