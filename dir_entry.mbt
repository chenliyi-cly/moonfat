///|
pub const ATTR_READ_ONLY : Int = 0x01

///|
pub const ATTR_HIDDEN : Int = 0x02

///|
pub const ATTR_SYSTEM : Int = 0x04

///|
pub const ATTR_VOLUME_ID : Int = 0x08

///|
pub const ATTR_DIRECTORY : Int = 0x10

///|
pub const ATTR_ARCHIVE : Int = 0x20

///|
pub const ATTR_LFN : Int = 0x0F

///|
pub const DIR_ENTRY_SIZE : Int = 32

///|
pub(all) struct RawEntry {
  offset : Int
  name : Bytes
  attr : Int
  nt_res : Int
  create_tenth : Int
  create_time : Int
  create_date : Int
  access_date : Int
  cluster : Int
  write_time : Int
  write_date : Int
  size : Int
} derive(Debug)

///|
pub fn RawEntry::is_end(self : RawEntry) -> Bool {
  self.name.length() > 0 && self.name[0] == b'\x00'
}

///|
pub fn RawEntry::is_deleted(self : RawEntry) -> Bool {
  self.name.length() > 0 && self.name[0] == b'\xE5'
}

///|
pub fn RawEntry::is_lfn(self : RawEntry) -> Bool {
  (self.attr & ATTR_LFN) == ATTR_LFN
}

///|
pub fn RawEntry::is_volume_id(self : RawEntry) -> Bool {
  (self.attr & ATTR_VOLUME_ID) != 0 && !self.is_lfn()
}

///|
pub fn RawEntry::is_dir(self : RawEntry) -> Bool {
  (self.attr & ATTR_DIRECTORY) != 0 && !self.is_lfn()
}

///|
pub fn RawEntry::is_dot(self : RawEntry) -> Bool {
  display_short_name(self.name) == "." || display_short_name(self.name) == ".."
}

///|
fn parse_raw_entry(
  data : Array[Byte],
  offset : Int,
  kind : FatKind,
) -> Result[RawEntry, FatError] {
  let name = match slice_bytes(data, offset, 11) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let attr = match u8_at(data, offset + 11) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let nt_res = match u8_at(data, offset + 12) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let create_tenth = match u8_at(data, offset + 13) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let create_time = match u16le_at(data, offset + 14) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let create_date = match u16le_at(data, offset + 16) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let access_date = match u16le_at(data, offset + 18) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let cluster_hi = match u16le_at(data, offset + 20) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let write_time = match u16le_at(data, offset + 22) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let write_date = match u16le_at(data, offset + 24) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let cluster_lo = match u16le_at(data, offset + 26) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let size = match u32le_at(data, offset + 28) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let cluster = match kind {
    Fat32 => ((cluster_hi & 0xFFFF) << 16) | (cluster_lo & 0xFFFF)
    _ => cluster_lo
  }
  Ok({
    offset,
    name,
    attr,
    nt_res,
    create_tenth,
    create_time,
    create_date,
    access_date,
    cluster,
    write_time,
    write_date,
    size,
  })
}

///|
fn write_raw_entry(
  data : Array[Byte],
  entry : RawEntry,
  kind : FatKind,
) -> Result[Unit, FatError] {
  match blit_bytes(data, entry.offset, entry.name) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u8(data, entry.offset + 11, entry.attr) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u8(data, entry.offset + 12, entry.nt_res) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u8(data, entry.offset + 13, entry.create_tenth) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u16le(data, entry.offset + 14, entry.create_time) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u16le(data, entry.offset + 16, entry.create_date) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u16le(data, entry.offset + 18, entry.access_date) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  let cluster_hi = match kind {
    Fat32 => (entry.cluster >> 16) & 0xFFFF
    _ => 0
  }
  match put_u16le(data, entry.offset + 20, cluster_hi) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u16le(data, entry.offset + 22, entry.write_time) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u16le(data, entry.offset + 24, entry.write_date) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u16le(data, entry.offset + 26, entry.cluster & 0xFFFF) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  put_u32le(data, entry.offset + 28, entry.size)
}

///|
fn lfn_unit_at(
  data : Array[Byte],
  offset : Int,
  index : Int,
) -> Result[Int, FatError] {
  // 0..4 at +1, 5..10 at +14, 11..12 at +28
  let byte_off = if index < 5 {
    offset + 1 + index * 2
  } else if index < 11 {
    offset + 14 + (index - 5) * 2
  } else {
    offset + 28 + (index - 11) * 2
  }
  u16le_at(data, byte_off)
}

///|
fn put_lfn_unit(
  data : Array[Byte],
  offset : Int,
  index : Int,
  unit : Int,
) -> Result[Unit, FatError] {
  let byte_off = if index < 5 {
    offset + 1 + index * 2
  } else if index < 11 {
    offset + 14 + (index - 5) * 2
  } else {
    offset + 28 + (index - 11) * 2
  }
  put_u16le(data, byte_off, unit)
}

///|
fn decode_lfn_chunk(
  data : Array[Byte],
  offset : Int,
) -> Result[Array[Int], FatError] {
  let units : Array[Int] = []
  for i = 0; i < 13; i = i + 1 {
    units.push(
      match lfn_unit_at(data, offset, i) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      },
    )
  }
  Ok(units)
}

///|
fn encode_lfn_chunk(
  data : Array[Byte],
  offset : Int,
  seq : Int,
  last : Bool,
  checksum : Int,
  units : Array[Int],
  start : Int,
) -> Result[Unit, FatError] {
  match fill_bytes(data, offset, 32, b'\x00') {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  let ord = seq | (if last { 0x40 } else { 0 })
  match put_u8(data, offset, ord) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u8(data, offset + 11, ATTR_LFN) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u8(data, offset + 12, 0) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u8(data, offset + 13, checksum) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match put_u16le(data, offset + 26, 0) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  for i = 0; i < 13; i = i + 1 {
    let idx = start + i
    let unit = if idx < units.length() {
      units[idx]
    } else if idx == units.length() {
      0
    } else {
      0xFFFF
    }
    match put_lfn_unit(data, offset, i, unit) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
pub(all) struct DirRecord {
  name : String
  short_name : Bytes
  attr : Int
  cluster : Int
  size : Int
  short_offset : Int
  lfn_offsets : Array[Int]
  write_time : Int
  write_date : Int
} derive(Debug)

///|
pub fn DirRecord::is_dir(self : DirRecord) -> Bool {
  (self.attr & ATTR_DIRECTORY) != 0
}

///|
pub fn DirRecord::is_volume_id(self : DirRecord) -> Bool {
  (self.attr & ATTR_VOLUME_ID) != 0
}

///|
pub fn DirRecord::is_dot(self : DirRecord) -> Bool {
  self.name == "." || self.name == ".."
}

///|
/// Public directory listing item.
pub(all) struct Entry {
  name : String
  short_name : String
  attr : Int
  cluster : Int
  size : Int
  is_dir : Bool
  write : DosTime
} derive(Debug)

///|
fn record_to_entry(record : DirRecord) -> Entry {
  {
    name: record.name,
    short_name: display_short_name(record.short_name),
    attr: record.attr,
    cluster: record.cluster,
    size: record.size,
    is_dir: record.is_dir(),
    write: unpack_dos_stamp(record.write_date, record.write_time),
  }
}
