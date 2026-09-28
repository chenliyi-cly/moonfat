///|
fn read_cluster_bytes(
  data : Array[Byte],
  layout : Layout,
  cluster : Int,
) -> Result[Bytes, FatError] {
  let sector = match layout.cluster_sector(cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  slice_bytes(
    data,
    sector * layout.bytes_per_sector,
    layout.bytes_per_cluster(),
  )
}

///|
fn write_cluster_bytes(
  data : Array[Byte],
  layout : Layout,
  cluster : Int,
  payload : Bytes,
  payload_off : Int,
  payload_len : Int,
) -> Result[Unit, FatError] {
  let sector = match layout.cluster_sector(cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let dest = sector * layout.bytes_per_sector
  match fill_bytes(data, dest, layout.bytes_per_cluster(), b'\x00') {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  let mut i = 0
  while i < payload_len {
    data[dest + i] = payload[payload_off + i]
    i = i + 1
  }
  Ok(())
}

///|
fn read_file_bytes(
  data : Array[Byte],
  layout : Layout,
  cluster : Int,
  size : Int,
) -> Result[Bytes, FatError] {
  if size < 0 {
    return Err(Corrupt("negative file size"))
  }
  if size == 0 {
    return Ok(Bytes::make(0, b'\x00'))
  }
  let chain = match follow_chain(data, layout, cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let needed = (size + layout.bytes_per_cluster() - 1) /
    layout.bytes_per_cluster()
  if chain.length() < needed {
    return Err(Corrupt("cluster chain is shorter than the directory size"))
  }
  let out = Array::make(size, b'\x00')
  let mut copied = 0
  let mut i = 0
  while copied < size && i < chain.length() {
    let chunk = match read_cluster_bytes(data, layout, chain[i]) {
      Err(err) => return Err(err)
      Ok(ok_val) => ok_val
    }
    let take = size - copied
    let n = if take < chunk.length() { take } else { chunk.length() }
    for j = 0; j < n; j = j + 1 {
      out[copied + j] = chunk[j]
    }
    copied = copied + n
    i = i + 1
  }
  Ok(Bytes::from_array(out))
}

///|
fn write_file_bytes(
  data : Array[Byte],
  layout : Layout,
  payload : Bytes,
  old_cluster : Int,
) -> Result[Int, FatError] {
  if old_cluster != 0 {
    match free_chain(data, layout, old_cluster) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
  }
  if payload.length() == 0 {
    return Ok(0)
  }
  let cluster_size = layout.bytes_per_cluster()
  let count = (payload.length() + cluster_size - 1) / cluster_size
  let first = match alloc_chain(data, layout, count, 2) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let chain = match follow_chain(data, layout, first) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let mut offset = 0
  for i = 0; i < chain.length(); i = i + 1 {
    let remaining = payload.length() - offset
    let n = if remaining < cluster_size { remaining } else { cluster_size }
    match write_cluster_bytes(data, layout, chain[i], payload, offset, n) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
    offset = offset + n
  }
  Ok(first)
}

///|
fn directory_is_empty(
  data : Array[Byte],
  layout : Layout,
  cluster : Int,
) -> Result[Bool, FatError] {
  let records = match read_directory(data, layout, cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  for i = 0; i < records.length(); i = i + 1 {
    if !records[i].is_dot() && !records[i].is_volume_id() {
      return Ok(false)
    }
  }
  Ok(true)
}
