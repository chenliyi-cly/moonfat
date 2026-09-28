///|
fn fat_entry_offset(layout : Layout, cluster : Int) -> Result[Int, FatError] {
  if cluster < 0 || cluster > layout.cluster_count + 1 {
    return Err(BadCluster(cluster))
  }
  match layout.kind {
    Fat12 => Ok(cluster + cluster / 2)
    Fat16 => Ok(cluster * 2)
    Fat32 => Ok(cluster * 4)
  }
}

///|
fn fat_base(layout : Layout, fat_index : Int) -> Int {
  (layout.first_fat_sector + fat_index * layout.fat_sectors) *
  layout.bytes_per_sector
}

///|
fn read_fat_raw(
  data : Array[Byte],
  layout : Layout,
  cluster : Int,
) -> Result[Int, FatError] {
  let rel = match fat_entry_offset(layout, cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let base = fat_base(layout, 0)
  match layout.kind {
    Fat12 => {
      let packed = match u16le_at(data, base + rel) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      if cluster % 2 == 0 {
        Ok(packed & 0x0FFF)
      } else {
        Ok((packed >> 4) & 0x0FFF)
      }
    }
    Fat16 => u16le_at(data, base + rel)
    Fat32 => {
      let b0 = match u8_at(data, base + rel) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      let b1 = match u8_at(data, base + rel + 1) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      let b2 = match u8_at(data, base + rel + 2) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      let b3 = match u8_at(data, base + rel + 3) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      Ok(b0 | (b1 << 8) | (b2 << 16) | ((b3 & 15) << 24))
    }
  }
}

///|
fn write_fat_copy(
  data : Array[Byte],
  layout : Layout,
  fat_index : Int,
  cluster : Int,
  value : Int,
) -> Result[Unit, FatError] {
  let rel = match fat_entry_offset(layout, cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let base = fat_base(layout, fat_index)
  match layout.kind {
    Fat12 => {
      let packed = match u16le_at(data, base + rel) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      let next = if cluster % 2 == 0 {
        (packed & 0xF000) | (value & 0x0FFF)
      } else {
        (packed & 0x000F) | ((value & 0x0FFF) << 4)
      }
      put_u16le(data, base + rel, next)
    }
    Fat16 => put_u16le(data, base + rel, value & 0xFFFF)
    Fat32 => {
      let off = base + rel
      if off < 0 || off + 3 >= data.length() {
        return Err(Truncated("fat32-entry", off + 4, data.length()))
      }
      let reserved = data[off + 3].to_int() & 240
      data[off] = (value & 255).to_byte()
      data[off + 1] = ((value >> 8) & 255).to_byte()
      data[off + 2] = ((value >> 16) & 255).to_byte()
      data[off + 3] = (((value >> 24) & 15) | reserved).to_byte()
      Ok(())
    }
  }
}

///|
fn write_fat_entry(
  data : Array[Byte],
  layout : Layout,
  cluster : Int,
  value : Int,
) -> Result[Unit, FatError] {
  for i = 0; i < layout.fat_count; i = i + 1 {
    match write_fat_copy(data, layout, i, cluster, value) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn init_fat_tables(
  data : Array[Byte],
  layout : Layout,
) -> Result[Unit, FatError] {
  let media = layout.media.to_int()
  let fat0 = match layout.kind {
    Fat12 => 0xF00 | media
    Fat16 => 0xFF00 | media
    Fat32 => 0x0FFFFF00 | media
  }
  for i = 0; i < layout.fat_count; i = i + 1 {
    let base = fat_base(layout, i)
    match fill_bytes(data, base, layout.fat_bytes(), b'\x00') {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
  }
  match write_fat_entry(data, layout, 0, fat0) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match write_fat_entry(data, layout, 1, layout.kind.eoc_value()) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match layout.kind {
    Fat32 =>
      match
        write_fat_entry(
          data,
          layout,
          layout.root_cluster,
          layout.kind.eoc_value(),
        ) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
    _ => ()
  }
  Ok(())
}

///|
fn follow_chain(
  data : Array[Byte],
  layout : Layout,
  start : Int,
) -> Result[Array[Int], FatError] {
  if start == 0 {
    return Ok([])
  }
  if start < 2 {
    return Err(BadCluster(start))
  }
  let clusters : Array[Int] = []
  let mut cluster = start
  let mut steps = 0
  while steps <= layout.cluster_count + 2 {
    if cluster < 2 || cluster > layout.cluster_count + 1 {
      return Err(BadCluster(cluster))
    }
    for i = 0; i < clusters.length(); i = i + 1 {
      if clusters[i] == cluster {
        return Err(ChainLoop(cluster))
      }
    }
    clusters.push(cluster)
    let next = match read_fat_raw(data, layout, cluster) {
      Err(err) => return Err(err)
      Ok(ok_val) => ok_val
    }
    if layout.kind.is_bad(next) {
      return Err(BadCluster(cluster))
    }
    if layout.kind.is_eoc(next) {
      return Ok(clusters)
    }
    if next == 0 {
      return Err(Corrupt("cluster \{cluster} points at a free FAT entry"))
    }
    cluster = next
    steps = steps + 1
  }
  Err(ChainLoop(start))
}

///|
fn alloc_cluster(
  data : Array[Byte],
  layout : Layout,
  hint : Int,
) -> Result[Int, FatError] {
  let begin = if hint >= 2 { hint } else { 2 }
  let last = layout.cluster_count + 1
  let mut cluster = begin
  while cluster <= last {
    let value = match read_fat_raw(data, layout, cluster) {
      Err(err) => return Err(err)
      Ok(ok_val) => ok_val
    }
    if value == 0 {
      match write_fat_entry(data, layout, cluster, layout.kind.eoc_value()) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      return Ok(cluster)
    }
    cluster = cluster + 1
  }
  cluster = 2
  while cluster < begin {
    let value = match read_fat_raw(data, layout, cluster) {
      Err(err) => return Err(err)
      Ok(ok_val) => ok_val
    }
    if value == 0 {
      match write_fat_entry(data, layout, cluster, layout.kind.eoc_value()) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      return Ok(cluster)
    }
    cluster = cluster + 1
  }
  Err(NoSpace)
}

///|
fn alloc_chain(
  data : Array[Byte],
  layout : Layout,
  count : Int,
  hint : Int,
) -> Result[Int, FatError] {
  if count <= 0 {
    return Ok(0)
  }
  let first = match alloc_cluster(data, layout, hint) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let mut prev = first
  let mut remaining = count - 1
  while remaining > 0 {
    let next = match alloc_cluster(data, layout, prev + 1) {
      Err(err) => return Err(err)
      Ok(ok_val) => ok_val
    }
    match write_fat_entry(data, layout, prev, next) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
    prev = next
    remaining = remaining - 1
  }
  Ok(first)
}

///|
fn free_chain(
  data : Array[Byte],
  layout : Layout,
  start : Int,
) -> Result[Unit, FatError] {
  let clusters = match follow_chain(data, layout, start) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  for i = 0; i < clusters.length(); i = i + 1 {
    match write_fat_entry(data, layout, clusters[i], 0) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
  }
  Ok(())
}

///|
fn extend_chain(
  data : Array[Byte],
  layout : Layout,
  start : Int,
  extra : Int,
) -> Result[Int, FatError] {
  if extra <= 0 {
    return Ok(start)
  }
  if start == 0 {
    return alloc_chain(data, layout, extra, 2)
  }
  let clusters = match follow_chain(data, layout, start) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  if clusters.length() == 0 {
    return alloc_chain(data, layout, extra, 2)
  }
  let last = clusters[clusters.length() - 1]
  let more = match alloc_chain(data, layout, extra, last + 1) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  match write_fat_entry(data, layout, last, more) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  Ok(start)
}

///|
fn chain_byte_length(layout : Layout, clusters : Array[Int]) -> Int {
  clusters.length() * layout.bytes_per_cluster()
}

///|
fn count_free_clusters(
  data : Array[Byte],
  layout : Layout,
) -> Result[Int, FatError] {
  let mut free = 0
  for cluster = 2; cluster <= layout.cluster_count + 1; cluster = cluster + 1 {
    let value = match read_fat_raw(data, layout, cluster) {
      Err(err) => return Err(err)
      Ok(ok_val) => ok_val
    }
    if value == 0 {
      free = free + 1
    }
  }
  Ok(free)
}
