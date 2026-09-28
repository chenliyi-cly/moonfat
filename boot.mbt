///|
/// On-disk FAT kind selected from cluster count, per the Microsoft FAT spec.
pub(all) enum FatKind {
  Fat12
  Fat16
  Fat32
} derive(Eq, Debug)

///|
pub fn FatKind::name(self : FatKind) -> String {
  match self {
    Fat12 => "FAT12"
    Fat16 => "FAT16"
    Fat32 => "FAT32"
  }
}

///|
pub fn FatKind::bits(self : FatKind) -> Int {
  match self {
    Fat12 => 12
    Fat16 => 16
    Fat32 => 32
  }
}

///|
pub fn FatKind::eoc_value(self : FatKind) -> Int {
  match self {
    Fat12 => 0xFFF
    Fat16 => 0xFFFF
    Fat32 => 0x0FFFFFFF
  }
}

///|
pub fn FatKind::bad_value(self : FatKind) -> Int {
  match self {
    Fat12 => 0xFF7
    Fat16 => 0xFFF7
    Fat32 => 0x0FFFFFF7
  }
}

///|
pub fn FatKind::is_eoc(self : FatKind, value : Int) -> Bool {
  match self {
    Fat12 => value >= 0xFF8
    Fat16 => value >= 0xFFF8
    Fat32 => (value & 0x0FFFFFFF) >= 0x0FFFFFF8
  }
}

///|
pub fn FatKind::is_bad(self : FatKind, value : Int) -> Bool {
  match self {
    Fat12 => (value & 0x0FFF) == 0xFF7
    Fat16 => (value & 0xFFFF) == 0xFFF7
    Fat32 => (value & 0x0FFFFFFF) == 0x0FFFFFF7
  }
}

///|
/// Cached geometry of a mounted or freshly formatted volume.
pub(all) struct Layout {
  kind : FatKind
  bytes_per_sector : Int
  sectors_per_cluster : Int
  reserved_sectors : Int
  fat_count : Int
  fat_sectors : Int
  root_entries : Int
  root_dir_sectors : Int
  first_fat_sector : Int
  first_root_sector : Int
  first_data_sector : Int
  cluster_count : Int
  root_cluster : Int
  total_sectors : Int
  media : Byte
  volume_id : Int
  label : String
  fsinfo_sector : Int
  backup_boot_sector : Int
} derive(Debug)

///|
pub fn Layout::bytes_per_cluster(self : Layout) -> Int {
  self.bytes_per_sector * self.sectors_per_cluster
}

///|
pub fn Layout::fat_bytes(self : Layout) -> Int {
  self.fat_sectors * self.bytes_per_sector
}

///|
pub fn Layout::cluster_sector(
  self : Layout,
  cluster : Int,
) -> Result[Int, FatError] {
  if cluster < 2 || cluster > self.cluster_count + 1 {
    Err(BadCluster(cluster))
  } else {
    Ok(self.first_data_sector + (cluster - 2) * self.sectors_per_cluster)
  }
}

///|
pub fn Layout::byte_offset(self : Layout, sector : Int) -> Int {
  sector * self.bytes_per_sector
}

///|
fn fat_kind_from_clusters(cluster_count : Int) -> FatKind {
  if cluster_count < 4085 {
    Fat12
  } else if cluster_count < 65525 {
    Fat16
  } else {
    Fat32
  }
}

///|
fn decode_label11(data : Array[Byte], offset : Int) -> String {
  match slice_bytes(data, offset, 11) {
    Err(_) => ""
    Ok(raw) => ascii_from_padded(raw)
  }
}

///|
fn decode_oem(data : Array[Byte]) -> String {
  match slice_bytes(data, 3, 8) {
    Err(_) => ""
    Ok(raw) => ascii_from_padded(raw)
  }
}

///|
pub fn parse_layout(data : Array[Byte]) -> Result[Layout, FatError] {
  if data.length() < 512 {
    return Err(Truncated("boot", 512, data.length()))
  }
  let sig0 = data[510]
  let sig1 = data[511]
  if sig0 != b'\x55' || sig1 != b'\xAA' {
    return Err(InvalidBoot("missing 0x55AA signature"))
  }
  let bytes_per_sector = match u16le_at(data, 11) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let sectors_per_cluster = match u8_at(data, 13) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let reserved_sectors = match u16le_at(data, 14) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let fat_count = match u8_at(data, 16) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let root_entries = match u16le_at(data, 17) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let total_sectors_16 = match u16le_at(data, 19) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let media = data[21]
  let fat_sectors_16 = match u16le_at(data, 22) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let total_sectors_32 = match u32le_at(data, 32) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  if !power_of_two(bytes_per_sector) ||
    bytes_per_sector < 512 ||
    bytes_per_sector > 4096 {
    return Err(
      InvalidBoot("bytes per sector must be 512..4096 and a power of two"),
    )
  }
  if !power_of_two(sectors_per_cluster) || sectors_per_cluster > 128 {
    return Err(InvalidBoot("sectors per cluster must be a power of two <= 128"))
  }
  if reserved_sectors <= 0 {
    return Err(InvalidBoot("reserved sector count must be positive"))
  }
  if fat_count <= 0 {
    return Err(InvalidBoot("FAT count must be positive"))
  }
  let total_sectors = if total_sectors_16 != 0 {
    total_sectors_16
  } else {
    total_sectors_32
  }
  if total_sectors <= 0 {
    return Err(InvalidBoot("total sector count is zero"))
  }
  let fat_sectors_32 = if fat_sectors_16 == 0 {
    match u32le_at(data, 36) {
      Err(err) => return Err(err)
      Ok(ok_val) => ok_val
    }
  } else {
    0
  }
  let fat_sectors = if fat_sectors_16 != 0 {
    fat_sectors_16
  } else {
    fat_sectors_32
  }
  if fat_sectors <= 0 {
    return Err(InvalidBoot("FAT size is zero"))
  }
  let root_dir_sectors = (root_entries * 32 + bytes_per_sector - 1) /
    bytes_per_sector
  let first_fat_sector = reserved_sectors
  let first_root_sector = reserved_sectors + fat_count * fat_sectors
  let first_data_sector = first_root_sector + root_dir_sectors
  if first_data_sector >= total_sectors {
    return Err(InvalidBoot("data region starts past the end of the volume"))
  }
  let cluster_count = (total_sectors - first_data_sector) / sectors_per_cluster
  if cluster_count <= 0 {
    return Err(InvalidBoot("no data clusters"))
  }
  let kind = fat_kind_from_clusters(cluster_count)
  let root_cluster = match kind {
    Fat32 => {
      let value = match u32le_at(data, 44) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      if value < 2 {
        2
      } else {
        value
      }
    }
    _ => 0
  }
  let fsinfo_sector = match kind {
    Fat32 =>
      match u16le_at(data, 48) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
    _ => 0
  }
  let backup_boot_sector = match kind {
    Fat32 =>
      match u16le_at(data, 50) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
    _ => 0
  }
  let ext_offset = match kind {
    Fat32 => 66
    _ => 38
  }
  let ext_sig = match u8_at(data, ext_offset) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let volume_id = if ext_sig == 0x29 {
    match u32le_at(data, ext_offset + 1) {
      Err(err) => return Err(err)
      Ok(ok_val) => ok_val
    }
  } else {
    0
  }
  let label = if ext_sig == 0x29 {
    decode_label11(data, ext_offset + 5)
  } else {
    ""
  }
  let needed = total_sectors * bytes_per_sector
  if data.length() < needed {
    return Err(Truncated("volume", needed, data.length()))
  }
  let _ = decode_oem(data)
  Ok({
    kind,
    bytes_per_sector,
    sectors_per_cluster,
    reserved_sectors,
    fat_count,
    fat_sectors,
    root_entries,
    root_dir_sectors,
    first_fat_sector,
    first_root_sector,
    first_data_sector,
    cluster_count,
    root_cluster,
    total_sectors,
    media,
    volume_id,
    label,
    fsinfo_sector,
    backup_boot_sector,
  })
}

///|
fn write_label11(
  data : Array[Byte],
  offset : Int,
  label : String,
) -> Result[Unit, FatError] {
  let padded = match ascii_pad11(label) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  blit_bytes(data, offset, padded)
}

///|
fn write_ascii_field(
  data : Array[Byte],
  offset : Int,
  text : String,
  width : Int,
) -> Result[Unit, FatError] {
  match fill_bytes(data, offset, width, b' ') {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  let mut i = 0
  while i < text.length() && i < width {
    let code = text[i].to_int()
    if code < 32 || code > 126 {
      return Err(InvalidName(text))
    }
    data[offset + i] = code.to_byte()
    i = i + 1
  }
  Ok(())
}

///|
fn write_boot_sector(
  data : Array[Byte],
  layout : Layout,
) -> Result[Unit, FatError] {
  let bps = layout.bytes_per_sector
  if data.length() < bps {
    return Err(Truncated("boot", bps, data.length()))
  }
  match fill_bytes(data, 0, bps, b'\x00') {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match layout.kind {
    Fat32 => {
      data[0] = b'\xEB'
      data[1] = b'\x58'
      data[2] = b'\x90'
    }
    _ => {
      data[0] = b'\xEB'
      data[1] = b'\x3C'
      data[2] = b'\x90'
    }
  }
  match write_ascii_field(data, 3, "MSDOS5.0", 8) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u16le(data, 11, bps) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u8(data, 13, layout.sectors_per_cluster) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u16le(data, 14, layout.reserved_sectors) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u8(data, 16, layout.fat_count) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u16le(data, 17, layout.root_entries) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  if layout.total_sectors < 0x10000 && layout.kind != Fat32 {
    match put_u16le(data, 19, layout.total_sectors) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
    match put_u32le(data, 32, 0) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
  } else {
    match put_u16le(data, 19, 0) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
    match put_u32le(data, 32, layout.total_sectors) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
  }
  match put_u8(data, 21, layout.media.to_int()) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match layout.kind {
    Fat32 =>
      match put_u16le(data, 22, 0) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
    _ =>
      match put_u16le(data, 22, layout.fat_sectors) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
  }
  match put_u16le(data, 24, 63) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u16le(data, 26, 255) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u32le(data, 28, 0) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match layout.kind {
    Fat32 => {
      match put_u32le(data, 36, layout.fat_sectors) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match put_u16le(data, 40, 0) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match put_u16le(data, 42, 0) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match put_u32le(data, 44, layout.root_cluster) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match put_u16le(data, 48, layout.fsinfo_sector) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match put_u16le(data, 50, layout.backup_boot_sector) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match put_u8(data, 64, 0x80) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match put_u8(data, 65, 0) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match put_u8(data, 66, 0x29) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match put_u32le(data, 67, layout.volume_id) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match write_label11(data, 71, layout.label) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match write_ascii_field(data, 82, "FAT32", 8) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
    }
    Fat16 => {
      match put_u8(data, 36, 0x80) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match put_u8(data, 37, 0) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match put_u8(data, 38, 0x29) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match put_u32le(data, 39, layout.volume_id) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match write_label11(data, 43, layout.label) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match write_ascii_field(data, 54, "FAT16", 8) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
    }
    Fat12 => {
      match put_u8(data, 36, 0x00) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match put_u8(data, 37, 0) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match put_u8(data, 38, 0x29) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match put_u32le(data, 39, layout.volume_id) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match write_label11(data, 43, layout.label) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      match write_ascii_field(data, 54, "FAT12", 8) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
    }
  }
  data[bps - 2] = b'\x55'
  data[bps - 1] = b'\xAA'
  Ok(())
}

///|
fn write_fsinfo(
  data : Array[Byte],
  layout : Layout,
  free_count : Int,
  next_free : Int,
) -> Result[Unit, FatError] {
  if layout.kind != Fat32 || layout.fsinfo_sector <= 0 {
    return Ok(())
  }
  let offset = layout.fsinfo_sector * layout.bytes_per_sector
  match fill_bytes(data, offset, layout.bytes_per_sector, b'\x00') {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u32le(data, offset, 0x41615252) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u32le(data, offset + 484, 0x61417272) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u32le(data, offset + 488, free_count) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u32le(data, offset + 492, next_free) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  if offset + 511 >= data.length() {
    return Err(Truncated("fsinfo", offset + 512, data.length()))
  }
  data[offset + 508] = b'\x00'
  data[offset + 509] = b'\x00'
  data[offset + 510] = b'\x55'
  data[offset + 511] = b'\xAA'
  Ok(())
}
