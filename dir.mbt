///|
fn static_root(layout : Layout) -> Bool {
  layout.kind != Fat32
}

///|
fn root_cluster_of(layout : Layout) -> Int {
  match layout.kind {
    Fat32 => layout.root_cluster
    _ => 0
  }
}

///|
fn directory_extent(
  data : Array[Byte],
  layout : Layout,
  dir_cluster : Int,
) -> Result[Array[(Int, Int)], FatError] {
  // pairs of (byte_offset, length)
  if dir_cluster == 0 && static_root(layout) {
    let offset = layout.first_root_sector * layout.bytes_per_sector
    let length = layout.root_dir_sectors * layout.bytes_per_sector
    return Ok([(offset, length)])
  }
  let cluster = if dir_cluster == 0 {
    root_cluster_of(layout)
  } else {
    dir_cluster
  }
  let chain = match follow_chain(data, layout, cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let extents : Array[(Int, Int)] = []
  for i = 0; i < chain.length(); i = i + 1 {
    let sector = match layout.cluster_sector(chain[i]) {
      Err(err) => return Err(err)
      Ok(ok_val) => ok_val
    }
    extents.push((sector * layout.bytes_per_sector, layout.bytes_per_cluster()))
  }
  Ok(extents)
}

///|
fn directory_capacity(
  data : Array[Byte],
  layout : Layout,
  dir_cluster : Int,
) -> Result[Int, FatError] {
  let extents = match directory_extent(data, layout, dir_cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let mut bytes = 0
  for i = 0; i < extents.length(); i = i + 1 {
    bytes = bytes + extents[i].1
  }
  Ok(bytes / DIR_ENTRY_SIZE)
}

///|
fn slot_offset(
  data : Array[Byte],
  layout : Layout,
  dir_cluster : Int,
  index : Int,
) -> Result[Int, FatError] {
  let extents = match directory_extent(data, layout, dir_cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let mut remaining = index * DIR_ENTRY_SIZE
  for i = 0; i < extents.length(); i = i + 1 {
    if remaining < extents[i].1 {
      return Ok(extents[i].0 + remaining)
    }
    remaining = remaining - extents[i].1
  }
  Err(SlotExhausted)
}

///|
fn read_slot(
  data : Array[Byte],
  layout : Layout,
  dir_cluster : Int,
  index : Int,
) -> Result[RawEntry, FatError] {
  let offset = match slot_offset(data, layout, dir_cluster, index) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  parse_raw_entry(data, offset, layout.kind)
}

///|
fn read_directory(
  data : Array[Byte],
  layout : Layout,
  dir_cluster : Int,
) -> Result[Array[DirRecord], FatError] {
  let cap = match directory_capacity(data, layout, dir_cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let records : Array[DirRecord] = []
  let mut pending_name = ""
  let mut pending_offsets : Array[Int] = []
  let mut pending_checksum = -1
  let mut pending_seq = -1
  for i = 0; i < cap; i = i + 1 {
    let raw = match read_slot(data, layout, dir_cluster, i) {
      Err(err) => return Err(err)
      Ok(ok_val) => ok_val
    }
    if raw.is_end() {
      break
    }
    if raw.is_deleted() {
      pending_name = ""
      pending_offsets = []
      pending_checksum = -1
      pending_seq = -1
      continue
    }
    if raw.is_lfn() {
      let seq = raw.name[0].to_int()
      let last = (seq & 0x40) != 0
      let number = seq & 0x1F
      if number == 0 {
        pending_name = ""
        pending_offsets = []
        continue
      }
      let chunk = match decode_lfn_chunk(data, raw.offset) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      let piece = string_from_utf16(chunk)
      let checksum = match u8_at(data, raw.offset + 13) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      if last {
        pending_name = piece
        pending_offsets = [raw.offset]
        pending_checksum = checksum
        pending_seq = number
      } else if pending_seq == number + 1 && pending_checksum == checksum {
        pending_name = piece + pending_name
        pending_offsets.push(raw.offset)
        pending_seq = number
      } else {
        pending_name = piece
        pending_offsets = [raw.offset]
        pending_checksum = checksum
        pending_seq = number
      }
      continue
    }
    let short = raw.name
    let checksum = lfn_checksum(short)
    let long_name = if pending_name.length() > 0 && pending_checksum == checksum {
      pending_name
    } else {
      display_short_name(short)
    }
    records.push({
      name: long_name,
      short_name: short,
      attr: raw.attr,
      cluster: raw.cluster,
      size: raw.size,
      short_offset: raw.offset,
      lfn_offsets: pending_offsets,
      write_time: raw.write_time,
      write_date: raw.write_date,
    })
    pending_name = ""
    pending_offsets = []
    pending_checksum = -1
    pending_seq = -1
  }
  Ok(records)
}

///|
fn find_record(records : Array[DirRecord], name : String) -> DirRecord? {
  for i = 0; i < records.length(); i = i + 1 {
    if names_equal(records[i].name, name) ||
      names_equal(display_short_name(records[i].short_name), name) {
      return Some(records[i])
    }
  }
  None
}

///|
fn existing_short_names(records : Array[DirRecord]) -> Array[Bytes] {
  let names : Array[Bytes] = []
  for i = 0; i < records.length(); i = i + 1 {
    names.push(records[i].short_name)
  }
  names
}

///|
fn grow_directory(
  data : Array[Byte],
  layout : Layout,
  dir_cluster : Int,
) -> Result[Int, FatError] {
  if dir_cluster == 0 && static_root(layout) {
    return Err(NoSpace)
  }
  let cluster = if dir_cluster == 0 {
    root_cluster_of(layout)
  } else {
    dir_cluster
  }
  match extend_chain(data, layout, cluster, 1) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  let extra_chain = match follow_chain(data, layout, cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  if extra_chain.length() == 0 {
    return Err(Corrupt("directory cluster chain is empty"))
  }
  let extra = extra_chain[extra_chain.length() - 1]
  let sector = match layout.cluster_sector(extra) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  match
    fill_bytes(
      data,
      sector * layout.bytes_per_sector,
      layout.bytes_per_cluster(),
      b'\x00',
    ) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  Ok(cluster)
}

///|
fn first_byte(data : Array[Byte], offset : Int) -> Result[Int, FatError] {
  u8_at(data, offset)
}

///|
fn find_free_run(
  data : Array[Byte],
  layout : Layout,
  dir_cluster : Int,
  needed : Int,
) -> Result[Int, FatError] {
  let mut attempts = 0
  while attempts < 8 {
    let cap = match directory_capacity(data, layout, dir_cluster) {
      Err(err) => return Err(err)
      Ok(ok_val) => ok_val
    }
    let mut run = 0
    let mut start = -1
    for i = 0; i < cap; i = i + 1 {
      let offset = match slot_offset(data, layout, dir_cluster, i) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      let marker = match first_byte(data, offset) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      let free = marker == 0x00 || marker == 0xE5
      if free {
        if run == 0 {
          start = i
        }
        run = run + 1
        if run >= needed {
          return Ok(start)
        }
        if marker == 0x00 {
          // remainder of the directory is available
          if cap - start >= needed {
            return Ok(start)
          }
        }
      } else {
        run = 0
        start = -1
      }
    }
    match grow_directory(data, layout, dir_cluster) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
    attempts = attempts + 1
  }
  Err(NoSpace)
}

///|
fn stamp_now() -> (Int, Int) {
  let time = default_dos_time()
  (pack_dos_time(time), pack_dos_date(time))
}

///|
fn write_short_at(
  data : Array[Byte],
  layout : Layout,
  offset : Int,
  short_name : Bytes,
  attr : Int,
  cluster : Int,
  size : Int,
) -> Result[Unit, FatError] {
  let (write_time, write_date) = stamp_now()
  write_raw_entry(
    data,
    {
      offset,
      name: short_name,
      attr,
      nt_res: 0,
      create_tenth: 0,
      create_time: write_time,
      create_date: write_date,
      access_date: write_date,
      cluster,
      write_time,
      write_date,
      size,
    },
    layout.kind,
  )
}

///|
fn create_dir_item(
  data : Array[Byte],
  layout : Layout,
  dir_cluster : Int,
  name : String,
  attr : Int,
  cluster : Int,
  size : Int,
) -> Result[DirRecord, FatError] {
  if name.length() == 0 || name == "." || name == ".." {
    return Err(InvalidName(name))
  }
  let records = match read_directory(data, layout, dir_cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  match find_record(records, name) {
    Some(_) => return Err(AlreadyExists(name))
    None => ()
  }
  let short_name = match
    allocate_short_name(name, existing_short_names(records)) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let lfn = needs_lfn(name) || display_short_name(short_name) != name
  let lfn_count = if lfn { lfn_entry_count(name) } else { 0 }
  let needed = lfn_count + 1
  let start = match find_free_run(data, layout, dir_cluster, needed) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let units = utf16_units(name)
  let checksum = lfn_checksum(short_name)
  let lfn_offsets : Array[Int] = []
  if lfn {
    let mut seq = lfn_count
    let mut slot = start
    while seq >= 1 {
      let offset = match slot_offset(data, layout, dir_cluster, slot) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      let start_unit = (seq - 1) * 13
      match
        encode_lfn_chunk(
          data,
          offset,
          seq,
          seq == lfn_count,
          checksum,
          units,
          start_unit,
        ) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      lfn_offsets.push(offset)
      seq = seq - 1
      slot = slot + 1
    }
  }
  let short_slot = start + lfn_count
  let short_offset = match slot_offset(data, layout, dir_cluster, short_slot) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  match
    write_short_at(data, layout, short_offset, short_name, attr, cluster, size) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  Ok({
    name,
    short_name,
    attr,
    cluster,
    size,
    short_offset,
    lfn_offsets,
    write_time: pack_dos_time(default_dos_time()),
    write_date: pack_dos_date(default_dos_time()),
  })
}

///|
fn mark_deleted_offset(
  data : Array[Byte],
  offset : Int,
) -> Result[Unit, FatError] {
  put_u8(data, offset, 0xE5)
}

///|
fn delete_record(
  data : Array[Byte],
  record : DirRecord,
) -> Result[Unit, FatError] {
  for i = 0; i < record.lfn_offsets.length(); i = i + 1 {
    match mark_deleted_offset(data, record.lfn_offsets[i]) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
  }
  mark_deleted_offset(data, record.short_offset)
}

///|
fn update_record_size_cluster(
  data : Array[Byte],
  layout : Layout,
  record : DirRecord,
  cluster : Int,
  size : Int,
) -> Result[Unit, FatError] {
  let raw = match parse_raw_entry(data, record.short_offset, layout.kind) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  write_raw_entry(
    data,
    {
      offset: raw.offset,
      name: raw.name,
      attr: raw.attr,
      nt_res: raw.nt_res,
      create_tenth: raw.create_tenth,
      create_time: raw.create_time,
      create_date: raw.create_date,
      access_date: raw.access_date,
      cluster,
      write_time: pack_dos_time(default_dos_time()),
      write_date: pack_dos_date(default_dos_time()),
      size,
    },
    layout.kind,
  )
}

///|
fn init_subdirectory(
  data : Array[Byte],
  layout : Layout,
  cluster : Int,
  parent_cluster : Int,
) -> Result[Unit, FatError] {
  let sector = match layout.cluster_sector(cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let offset = sector * layout.bytes_per_sector
  match fill_bytes(data, offset, layout.bytes_per_cluster(), b'\x00') {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  let dot = pack_short_name(".", "")
  let dotdot = pack_short_name("..", "")
  match write_short_at(data, layout, offset, dot, ATTR_DIRECTORY, cluster, 0) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  let parent_stored = if parent_cluster == root_cluster_of(layout) {
    0
  } else {
    parent_cluster
  }
  write_short_at(
    data,
    layout,
    offset + DIR_ENTRY_SIZE,
    dotdot,
    ATTR_DIRECTORY,
    parent_stored,
    0,
  )
}
