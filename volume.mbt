///|
/// An in-memory FAT12/16/32 volume.
pub(all) struct Volume {
  mut data : Array[Byte]
  layout : Layout
}

///|
pub fn mount(data : Array[Byte]) -> Result[Volume, FatError] {
  let layout = match parse_layout(data) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  Ok({ data, layout })
}

///|
pub fn mount_bytes(bytes : Bytes) -> Result[Volume, FatError] {
  let data = Array::make(bytes.length(), b'\x00')
  for i = 0; i < bytes.length(); i = i + 1 {
    data[i] = bytes[i]
  }
  mount(data)
}

///|
pub fn mount_range(
  data : Array[Byte],
  offset : Int,
  length : Int,
) -> Result[Volume, FatError] {
  if offset < 0 || length <= 0 || offset + length > data.length() {
    return Err(Truncated("partition", offset + length, data.length()))
  }
  let slice = Array::make(length, b'\x00')
  for i = 0; i < length; i = i + 1 {
    slice[i] = data[offset + i]
  }
  mount(slice)
}

///|
pub fn Volume::kind(self : Volume) -> FatKind {
  self.layout.kind
}

///|
pub fn Volume::label(self : Volume) -> String {
  self.layout.label
}

///|
pub fn Volume::cluster_count(self : Volume) -> Int {
  self.layout.cluster_count
}

///|
pub fn Volume::total_bytes(self : Volume) -> Int {
  self.layout.total_sectors * self.layout.bytes_per_sector
}

///|
pub fn Volume::bytes_per_cluster(self : Volume) -> Int {
  self.layout.bytes_per_cluster()
}

///|
pub fn Volume::to_bytes(self : Volume) -> Bytes {
  Bytes::from_array(self.data)
}

///|
pub fn Volume::boot_preview(self : Volume) -> Result[Bytes, FatError] {
  slice_bytes(self.data, 0, self.layout.bytes_per_sector)
}

///|
fn Volume::walk_parts(
  self : Volume,
  parts : Array[String],
) -> Result[(Int, DirRecord?), FatError] {
  let mut dir_cluster = root_cluster_of(self.layout)
  if parts.length() == 0 {
    return Ok((dir_cluster, None))
  }
  let mut i = 0
  while i < parts.length() {
    let name = parts[i]
    if name == "." {
      i = i + 1
      continue
    }
    if name == ".." {
      if dir_cluster == root_cluster_of(self.layout) {
        i = i + 1
        continue
      }
      let records = match read_directory(self.data, self.layout, dir_cluster) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      match find_record(records, "..") {
        None => return Err(Corrupt("directory is missing .."))
        Some(parent) =>
          dir_cluster = if parent.cluster == 0 {
            root_cluster_of(self.layout)
          } else {
            parent.cluster
          }
      }
      i = i + 1
      continue
    }
    let records = match read_directory(self.data, self.layout, dir_cluster) {
      Err(err) => return Err(err)
      Ok(ok_val) => ok_val
    }
    match find_record(records, name) {
      None => {
        if i == parts.length() - 1 {
          return Ok((dir_cluster, None))
        }
        return Err(NotFound(name))
      }
      Some(record) => {
        if i == parts.length() - 1 {
          return Ok((dir_cluster, Some(record)))
        }
        if !record.is_dir() {
          return Err(NotDirectory(name))
        }
        dir_cluster = record.cluster
      }
    }
    i = i + 1
  }
  Ok((dir_cluster, None))
}

///|
pub fn Volume::list(
  self : Volume,
  path : String,
) -> Result[Array[Entry], FatError] {
  let parts = match split_path(path) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let (dir_cluster, last) = match self.walk_parts(parts) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let cluster = match last {
    None => dir_cluster
    Some(record) => {
      if !record.is_dir() {
        return Err(NotDirectory(path))
      }
      record.cluster
    }
  }
  let records = match read_directory(self.data, self.layout, cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let entries : Array[Entry] = []
  for i = 0; i < records.length(); i = i + 1 {
    if records[i].is_dot() || records[i].is_volume_id() {
      continue
    }
    entries.push(record_to_entry(records[i]))
  }
  Ok(entries)
}

///|
pub fn Volume::stat(self : Volume, path : String) -> Result[Entry, FatError] {
  let parts = match split_path(path) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  if parts.length() == 0 {
    return Ok({
      name: "/",
      short_name: "",
      attr: ATTR_DIRECTORY,
      cluster: root_cluster_of(self.layout),
      size: 0,
      is_dir: true,
      write: default_dos_time(),
    })
  }
  let (_, last) = match self.walk_parts(parts) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  match last {
    None => Err(NotFound(path))
    Some(record) => Ok(record_to_entry(record))
  }
}

///|
pub fn Volume::read_file(
  self : Volume,
  path : String,
) -> Result[Bytes, FatError] {
  let entry = match self.stat(path) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  if entry.is_dir {
    return Err(IsDirectory(path))
  }
  read_file_bytes(self.data, self.layout, entry.cluster, entry.size)
}

///|
pub fn Volume::mkdir(self : Volume, path : String) -> Result[Unit, FatError] {
  let parts = match split_path(path) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  if parts.length() == 0 {
    return Err(InvalidPath(path))
  }
  let name = parts[parts.length() - 1]
  let parent_parts : Array[String] = []
  for i = 0; i < parts.length() - 1; i = i + 1 {
    parent_parts.push(parts[i])
  }
  let (parent_cluster, last) = match self.walk_parts(parent_parts) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  if parent_parts.length() > 0 {
    match last {
      None => return Err(NotFound(path))
      Some(record) => if !record.is_dir() { return Err(NotDirectory(path)) }
    }
  }
  let dir_cluster = match last {
    None => parent_cluster
    Some(record) => record.cluster
  }
  let records = match read_directory(self.data, self.layout, dir_cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  match find_record(records, name) {
    Some(_) => return Err(AlreadyExists(path))
    None => ()
  }
  let cluster = match alloc_cluster(self.data, self.layout, 2) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  match init_subdirectory(self.data, self.layout, cluster, dir_cluster) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match
    create_dir_item(
      self.data,
      self.layout,
      dir_cluster,
      name,
      ATTR_DIRECTORY,
      cluster,
      0,
    ) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  Ok(())
}

///|
pub fn Volume::write_file(
  self : Volume,
  path : String,
  payload : Bytes,
) -> Result[Unit, FatError] {
  let parts = match split_path(path) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  if parts.length() == 0 {
    return Err(IsDirectory(path))
  }
  let name = parts[parts.length() - 1]
  let parent_parts : Array[String] = []
  for i = 0; i < parts.length() - 1; i = i + 1 {
    parent_parts.push(parts[i])
  }
  let (parent_cluster, last) = match self.walk_parts(parent_parts) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  if parent_parts.length() > 0 {
    match last {
      None => return Err(NotFound(path))
      Some(record) => if !record.is_dir() { return Err(NotDirectory(path)) }
    }
  }
  let dir_cluster = match last {
    None => parent_cluster
    Some(record) => record.cluster
  }
  let records = match read_directory(self.data, self.layout, dir_cluster) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  match find_record(records, name) {
    Some(record) => {
      if record.is_dir() {
        return Err(IsDirectory(path))
      }
      let cluster = match
        write_file_bytes(self.data, self.layout, payload, record.cluster) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      update_record_size_cluster(
        self.data,
        self.layout,
        record,
        cluster,
        payload.length(),
      )
    }
    None => {
      let cluster = match write_file_bytes(self.data, self.layout, payload, 0) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      match
        create_dir_item(
          self.data,
          self.layout,
          dir_cluster,
          name,
          ATTR_ARCHIVE,
          cluster,
          payload.length(),
        ) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
      Ok(())
    }
  }
}

///|
pub fn Volume::remove(self : Volume, path : String) -> Result[Unit, FatError] {
  let parts = match split_path(path) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  if parts.length() == 0 {
    return Err(InvalidPath(path))
  }
  let (dir_cluster, last) = match self.walk_parts(parts) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  match last {
    None => Err(NotFound(path))
    Some(record) => {
      if record.is_dir() {
        let empty = match
          directory_is_empty(self.data, self.layout, record.cluster) {
          Err(err) => return Err(err)
          Ok(ok_val) => ok_val
        }
        if !empty {
          return Err(DirectoryNotEmpty(path))
        }
        match free_chain(self.data, self.layout, record.cluster) {
          Err(err) => return Err(err)
          Ok(_) => ()
        }
      } else if record.cluster != 0 {
        match free_chain(self.data, self.layout, record.cluster) {
          Err(err) => return Err(err)
          Ok(_) => ()
        }
      }
      let _ = dir_cluster
      delete_record(self.data, record)
    }
  }
}

///|
pub fn Volume::walk(
  self : Volume,
  path : String,
) -> Result[Array[Entry], FatError] {
  let out : Array[Entry] = []
  match self.walk_into(path, out) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  Ok(out)
}

///|
fn Volume::walk_into(
  self : Volume,
  path : String,
  out : Array[Entry],
) -> Result[Unit, FatError] {
  let entries = match self.list(path) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  for i = 0; i < entries.length(); i = i + 1 {
    out.push(entries[i])
    if entries[i].is_dir {
      match self.walk_into(join_path(path, entries[i].name), out) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
    }
  }
  Ok(())
}

///|
pub fn Volume::free_clusters(self : Volume) -> Result[Int, FatError] {
  count_free_clusters(self.data, self.layout)
}

///|
pub fn Volume::mkdir_p(self : Volume, path : String) -> Result[Unit, FatError] {
  let parts = match split_path(path) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let mut current = "/"
  for i = 0; i < parts.length(); i = i + 1 {
    current = join_path(current, parts[i])
    match self.stat(current) {
      Ok(entry) => if !entry.is_dir { return Err(NotDirectory(current)) }
      Err(NotFound(_)) =>
        match self.mkdir(current) {
          Err(err) => return Err(err)
          Ok(ok_val) => ok_val
        }
      Err(err) => return Err(err)
    }
  }
  Ok(())
}
