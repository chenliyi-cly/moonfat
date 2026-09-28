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
    volume_label: "FWIMG",
    volume_id: 0x46574D47,
  }).unwrap()
  vol.mkdir_p("/payload").unwrap()
  let blob = ascii("firmware-payload-v1")
  vol.write_file("/payload/app.bin", blob).unwrap()
  let got = vol.read_file("/payload/app.bin").unwrap()
  println("packed \{got.length()} bytes into \{vol.kind().name()}")
  println(@fat.hex_encode(got))
  let image = vol.to_bytes()
  println(
    "image \{image.length()} bytes free_clusters=\{vol.free_clusters().unwrap()}",
  )
  let mounted = @fat.mount_bytes(image).unwrap()
  let again = mounted.read_file("/payload/app.bin").unwrap()
  println("remount \{again.length()} bytes")
}
