///|
/// Parameters used to create a new in-memory FAT volume.
pub(all) struct FormatOptions {
  kind : FatKind
  bytes_per_sector : Int
  total_sectors : Int
  volume_label : String
  volume_id : Int
} derive(Debug)

///|
pub fn floppy_1440_options() -> FormatOptions {
  {
    kind: Fat12,
    bytes_per_sector: 512,
    total_sectors: 2880,
    volume_label: "MOONFAT",
    volume_id: 0x4D4F4F4E,
  }
}

///|
pub fn small_fat16_options() -> FormatOptions {
  {
    kind: Fat16,
    bytes_per_sector: 512,
    total_sectors: 4163,
    volume_label: "MOONFAT",
    volume_id: 0x4D4F4F4E,
  }
}

///|
pub fn min_fat32_options() -> FormatOptions {
  {
    kind: Fat32,
    bytes_per_sector: 512,
    total_sectors: 66581,
    volume_label: "MOONFAT",
    volume_id: 0x4D4F4F4E,
  }
}

///|
fn default_reserved(kind : FatKind) -> Int {
  match kind {
    Fat32 => 32
    _ => 1
  }
}

///|
fn default_root_entries(kind : FatKind) -> Int {
  match kind {
    Fat12 => 224
    Fat16 => 512
    Fat32 => 0
  }
}

///|
fn default_media(kind : FatKind, total_sectors : Int) -> Byte {
  if kind == Fat12 && total_sectors == 2880 {
    b'\xF0'
  } else {
    b'\xF8'
  }
}

///|
fn fat_sectors_for(
  kind : FatKind,
  clusters : Int,
  bytes_per_sector : Int,
) -> Int {
  let entries = clusters + 2
  let bits = kind.bits()
  let bytes = (entries * bits + 7) / 8
  (bytes + bytes_per_sector - 1) / bytes_per_sector
}

///|
fn compute_layout(options : FormatOptions) -> Result[Layout, FatError] {
  if !power_of_two(options.bytes_per_sector) || options.bytes_per_sector < 512 {
    return Err(InvalidBoot("bytes per sector must be a power of two >= 512"))
  }
  if options.total_sectors <= 0 {
    return Err(InvalidBoot("total sector count must be positive"))
  }
  let reserved = default_reserved(options.kind)
  let root_entries = default_root_entries(options.kind)
  let fat_count = 2
  let mut spc = 1
  let mut loops = 0
  while loops < 8 {
    let root_dir_sectors = (root_entries * 32 + options.bytes_per_sector - 1) /
      options.bytes_per_sector
    let mut fat_sectors = 1
    let mut stable = false
    let mut cluster_count = 0
    let mut inner = 0
    while inner < 16 {
      let first_data = reserved + fat_count * fat_sectors + root_dir_sectors
      if options.total_sectors <= first_data {
        break
      }
      cluster_count = (options.total_sectors - first_data) / spc
      let next_fat = fat_sectors_for(
        options.kind,
        cluster_count,
        options.bytes_per_sector,
      )
      if next_fat == fat_sectors {
        stable = true
        break
      }
      fat_sectors = next_fat
      inner = inner + 1
    }
    if stable && cluster_count > 0 {
      let detected = fat_kind_from_clusters(cluster_count)
      if detected == options.kind {
        let root_dir_sectors = (
            root_entries * 32 + options.bytes_per_sector - 1
          ) /
          options.bytes_per_sector
        let first_fat_sector = reserved
        let first_root_sector = reserved + fat_count * fat_sectors
        let first_data_sector = first_root_sector + root_dir_sectors
        let label = if options.volume_label.length() == 0 {
          "NO NAME"
        } else {
          options.volume_label
        }
        return Ok({
          kind: options.kind,
          bytes_per_sector: options.bytes_per_sector,
          sectors_per_cluster: spc,
          reserved_sectors: reserved,
          fat_count,
          fat_sectors,
          root_entries,
          root_dir_sectors,
          first_fat_sector,
          first_root_sector,
          first_data_sector,
          cluster_count,
          root_cluster: match options.kind {
            Fat32 => 2
            _ => 0
          },
          total_sectors: options.total_sectors,
          media: default_media(options.kind, options.total_sectors),
          volume_id: options.volume_id,
          label,
          fsinfo_sector: match options.kind {
            Fat32 => 1
            _ => 0
          },
          backup_boot_sector: match options.kind {
            Fat32 => 6
            _ => 0
          },
        })
      }
    }
    spc = spc * 2
    loops = loops + 1
  }
  Err(
    InvalidBoot(
      "cannot build a \{options.kind.name()} layout for \{options.total_sectors} sectors",
    ),
  )
}

///|
pub fn format_volume(options : FormatOptions) -> Result[Volume, FatError] {
  let layout = match compute_layout(options) {
    Err(err) => return Err(err)
    Ok(ok_val) => ok_val
  }
  let bytes = layout.total_sectors * layout.bytes_per_sector
  let data = Array::make(bytes, b'\x00')
  match write_boot_sector(data, layout) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match layout.kind {
    Fat32 => {
      let backup = layout.backup_boot_sector * layout.bytes_per_sector
      for i = 0; i < layout.bytes_per_sector; i = i + 1 {
        data[backup + i] = data[i]
      }
    }
    _ => ()
  }
  match init_fat_tables(data, layout) {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  match layout.kind {
    Fat32 => {
      let root_sector = match layout.cluster_sector(layout.root_cluster) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      match
        fill_bytes(
          data,
          root_sector * layout.bytes_per_sector,
          layout.bytes_per_cluster(),
          b'\x00',
        ) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
      match write_fsinfo(data, layout, layout.cluster_count - 1, 3) {
        Err(err) => return Err(err)
        Ok(_) => ()
      }
    }
    _ =>
      match
        fill_bytes(
          data,
          layout.first_root_sector * layout.bytes_per_sector,
          layout.root_dir_sectors * layout.bytes_per_sector,
          b'\x00',
        ) {
        Err(err) => return Err(err)
        Ok(ok_val) => ok_val
      }
  }
  if layout.label.length() > 0 && layout.label != "NO NAME" {
    match
      create_dir_item(
        data,
        layout,
        root_cluster_of(layout),
        layout.label,
        ATTR_VOLUME_ID,
        0,
        0,
      ) {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
  }
  Ok({ data, layout })
}

///|
pub fn format_floppy() -> Result[Volume, FatError] {
  format_volume(floppy_1440_options())
}

///|
pub fn format_fat16_small() -> Result[Volume, FatError] {
  format_volume(small_fat16_options())
}

///|
pub fn format_fat32_min() -> Result[Volume, FatError] {
  format_volume(min_fat32_options())
}
