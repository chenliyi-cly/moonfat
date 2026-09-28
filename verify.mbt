///|
/// One verifier finding. `cluster` is 0 when the issue is volume-wide.
pub(all) struct VerifyIssue {
  code : String
  message : String
  cluster : Int
} derive(Eq, Debug)

///|
fn issue(code : String, message : String, cluster : Int) -> VerifyIssue {
  { code, message, cluster }
}

///|
pub fn Volume::verify(self : Volume) -> Array[VerifyIssue] {
  let issues : Array[VerifyIssue] = []
  match parse_layout(self.data) {
    Err(err) => {
      issues.push(issue("VFY001", err.message(), 0))
      return issues
    }
    Ok(_) => ()
  }
  if self.data.length() != self.total_bytes() {
    issues.push(
      issue(
        "VFY002",
        "image length \{self.data.length()} does not match \{self.total_bytes()} byte layout",
        0,
      ),
    )
  }
  match self.layout.kind {
    Fat32 =>
      if self.layout.root_cluster < 2 {
        issues.push(
          issue(
            "VFY003",
            "FAT32 root cluster is invalid",
            self.layout.root_cluster,
          ),
        )
      }
    _ => ()
  }
  let used = Array::make(self.layout.cluster_count + 2, 0)
  self.verify_fat(issues, used)
  self.verify_tree(root_cluster_of(self.layout), "/", issues, used)
  self.verify_lost_clusters(issues, used)
  issues
}

///|
fn Volume::verify_fat(
  self : Volume,
  issues : Array[VerifyIssue],
  used : Array[Int],
) -> Unit {
  let media_entry = match read_fat_raw(self.data, self.layout, 0) {
    Err(err) => {
      issues.push(issue("VFY010", err.message(), 0))
      return
    }
    Ok(value) => value
  }
  if (media_entry & 0xFF) != self.layout.media.to_int() {
    issues.push(
      issue(
        "VFY011",
        "FAT[0] media nibble \{media_entry & 0xFF} != BPB media \{self.layout.media.to_int()}",
        0,
      ),
    )
  }
  match read_fat_raw(self.data, self.layout, 1) {
    Err(err) => issues.push(issue("VFY012", err.message(), 1))
    Ok(_) => ()
  }
  for cluster = 2
      cluster <= self.layout.cluster_count + 1
      cluster = cluster + 1 {
    match read_fat_raw(self.data, self.layout, cluster) {
      Err(err) => issues.push(issue("VFY013", err.message(), cluster))
      Ok(value) =>
        if self.layout.kind.is_bad(value) {
          used[cluster] = 2
        } else if value == 0 {
          used[cluster] = 0
        } else if self.layout.kind.is_eoc(value) ||
          (value >= 2 && value <= self.layout.cluster_count + 1) {
          used[cluster] = 1
        } else {
          issues.push(
            issue(
              "VFY014",
              "FAT[\{cluster}] has out-of-range next \{value}",
              cluster,
            ),
          )
        }
    }
  }
  if self.layout.fat_count >= 2 {
    let len = self.layout.fat_bytes()
    let a = fat_base(self.layout, 0)
    let b = fat_base(self.layout, 1)
    let mut differ = 0
    for i = 0; i < len; i = i + 1 {
      if self.data[a + i] != self.data[b + i] {
        differ = differ + 1
      }
    }
    if differ > 0 {
      issues.push(
        issue("VFY015", "FAT copy 0 and 1 differ in \{differ} bytes", 0),
      )
    }
  }
}

///|
fn Volume::verify_tree(
  self : Volume,
  dir_cluster : Int,
  path : String,
  issues : Array[VerifyIssue],
  used : Array[Int],
) -> Unit {
  match read_directory(self.data, self.layout, dir_cluster) {
    Err(err) =>
      issues.push(issue("VFY020", "\{path}: \{err.message()}", dir_cluster))
    Ok(records) =>
      for i = 0; i < records.length(); i = i + 1 {
        let record = records[i]
        if record.is_dot() {
          continue
        }
        if record.lfn_offsets.length() > 0 {
          let checksum = lfn_checksum(record.short_name)
          for j = 0; j < record.lfn_offsets.length(); j = j + 1 {
            match u8_at(self.data, record.lfn_offsets[j] + 13) {
              Err(_) =>
                issues.push(
                  issue("VFY021", "truncated LFN at \{path}", dir_cluster),
                )
              Ok(found) =>
                if found != checksum {
                  issues.push(
                    issue(
                      "VFY022",
                      "\{path}/\{record.name} LFN checksum mismatch",
                      dir_cluster,
                    ),
                  )
                }
            }
          }
        }
        if record.cluster == 0 &&
          record.size > 0 &&
          !record.is_dir() &&
          !record.is_volume_id() {
          issues.push(
            issue(
              "VFY023",
              "\{path}/\{record.name} has size \{record.size} but cluster 0",
              0,
            ),
          )
        }
        if record.cluster != 0 && !record.is_volume_id() {
          match follow_chain(self.data, self.layout, record.cluster) {
            Err(err) =>
              issues.push(
                issue(
                  "VFY024",
                  "\{path}/\{record.name}: \{err.message()}",
                  record.cluster,
                ),
              )
            Ok(chain) => {
              self.mark_chain(chain, path + "/" + record.name, issues, used)
              if !record.is_dir() {
                let capacity = chain_byte_length(self.layout, chain)
                if record.size > capacity {
                  issues.push(
                    issue(
                      "VFY025",
                      "\{path}/\{record.name} size \{record.size} exceeds chain \{capacity}",
                      record.cluster,
                    ),
                  )
                }
              }
              if record.is_dir() {
                self.verify_tree(
                  record.cluster,
                  join_path(path, record.name),
                  issues,
                  used,
                )
              }
            }
          }
        }
      }
  }
}

///|
fn Volume::mark_chain(
  self : Volume,
  chain : Array[Int],
  path : String,
  issues : Array[VerifyIssue],
  used : Array[Int],
) -> Unit {
  let _ = self
  for i = 0; i < chain.length(); i = i + 1 {
    let cluster = chain[i]
    if cluster < 2 || cluster >= used.length() {
      issues.push(
        issue("VFY030", "\{path} uses invalid cluster \{cluster}", cluster),
      )
      continue
    }
    if used[cluster] == 3 {
      issues.push(
        issue("VFY031", "\{path} cross-links cluster \{cluster}", cluster),
      )
    } else if used[cluster] == 2 {
      issues.push(
        issue("VFY032", "\{path} uses a bad cluster \{cluster}", cluster),
      )
    } else {
      used[cluster] = 3
    }
  }
}

///|
fn Volume::verify_lost_clusters(
  self : Volume,
  issues : Array[VerifyIssue],
  used : Array[Int],
) -> Unit {
  let mut lost = 0
  for cluster = 2
      cluster <= self.layout.cluster_count + 1
      cluster = cluster + 1 {
    if used[cluster] == 1 {
      lost = lost + 1
    }
  }
  if lost > 0 {
    issues.push(
      issue(
        "VFY040",
        "\{lost} allocated clusters are not reachable from directories",
        0,
      ),
    )
  }
}

///|
pub fn Volume::issue_codes(self : Volume) -> Array[String] {
  let issues = self.verify()
  let codes : Array[String] = []
  for i = 0; i < issues.length(); i = i + 1 {
    codes.push(issues[i].code)
  }
  codes
}
