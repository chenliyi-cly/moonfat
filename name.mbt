///|
fn is_sep(code : Int) -> Bool {
  code == 47 || code == 92
}

///|
pub fn split_path(path : String) -> Result[Array[String], FatError] {
  if path.length() == 0 {
    return Err(InvalidPath(path))
  }
  let parts : Array[String] = []
  let mut current = ""
  for i = 0; i < path.length(); i = i + 1 {
    let code = path[i].to_int()
    if code == 0 {
      return Err(InvalidPath(path))
    }
    if is_sep(code) {
      if current.length() > 0 {
        parts.push(current)
        current = ""
      }
    } else {
      current = current + path[i:i + 1].to_owned()
    }
  }
  if current.length() > 0 {
    parts.push(current)
  }
  for i = 0; i < parts.length(); i = i + 1 {
    if parts[i] == "." || parts[i] == ".." {
      continue
    }
    if parts[i].length() > 255 {
      return Err(InvalidName(parts[i]))
    }
  }
  Ok(parts)
}

///|
fn ascii_upper_code(code : Int) -> Int {
  if code >= 97 && code <= 122 {
    code - 32
  } else {
    code
  }
}

///|
fn names_equal(left : String, right : String) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for i = 0; i < left.length(); i = i + 1 {
    if ascii_upper_code(left[i].to_int()) != ascii_upper_code(right[i].to_int()) {
      return false
    }
  }
  true
}

///|
fn is_short_char(code : Int) -> Bool {
  if code >= 97 && code <= 122 {
    return true
  }
  if code >= 65 && code <= 90 {
    return true
  }
  if code >= 48 && code <= 57 {
    return true
  }
  code == 36 ||
  code == 37 ||
  code == 39 ||
  code == 45 ||
  code == 95 ||
  code == 64 ||
  code == 126 ||
  code == 96 ||
  code == 33 ||
  code == 40 ||
  code == 41 ||
  code == 123 ||
  code == 125 ||
  code == 94 ||
  code == 35 ||
  code == 38
}

///|
fn split_stem_ext(name : String) -> (String, String) {
  let mut dot = -1
  for i = 0; i < name.length(); i = i + 1 {
    if name[i].to_int() == 46 {
      dot = i
    }
  }
  if dot <= 0 || dot == name.length() - 1 {
    (name, "")
  } else {
    (name[0:dot].to_owned(), name[dot + 1:name.length()].to_owned())
  }
}

///|
fn sanitize_short_part(text : String, max : Int) -> (String, Bool) {
  let mut out = ""
  let mut lossy = false
  for i = 0; i < text.length(); i = i + 1 {
    let mut code = text[i].to_int()
    if code == 32 || code == 46 {
      lossy = true
      continue
    }
    if code >= 97 && code <= 122 {
      code = code - 32
    }
    if !is_short_char(code) {
      code = 95
      lossy = true
    }
    if out.length() < max {
      out = out + code.unsafe_to_char().to_string()
    } else {
      lossy = true
    }
  }
  if out.length() == 0 {
    ("X", true)
  } else {
    (out, lossy)
  }
}

///|
fn needs_lfn(name : String) -> Bool {
  if name == "." || name == ".." {
    return false
  }
  let (stem, ext) = split_stem_ext(name)
  if stem.length() == 0 || stem.length() > 8 || ext.length() > 3 {
    return true
  }
  for i = 0; i < name.length(); i = i + 1 {
    let code = name[i].to_int()
    if code >= 97 && code <= 122 {
      return true
    }
    if code == 46 {
      continue
    }
    if !is_short_char(code) {
      return true
    }
  }
  let mut dots = 0
  for i = 0; i < name.length(); i = i + 1 {
    if name[i].to_int() == 46 {
      dots = dots + 1
    }
  }
  dots > 1
}

///|
fn pack_short_name(stem : String, ext : String) -> Bytes {
  let out = Array::make(11, b' ')
  let mut i = 0
  while i < stem.length() && i < 8 {
    out[i] = stem[i].to_int().to_byte()
    i = i + 1
  }
  let mut j = 0
  while j < ext.length() && j < 3 {
    out[8 + j] = ext[j].to_int().to_byte()
    j = j + 1
  }
  Bytes::from_array(out)
}

///|
fn display_short_name(raw : Bytes) -> String {
  let name_bytes = Bytes::makei(8, i => raw[i])
  let ext_bytes = Bytes::makei(3, i => raw[8 + i])
  let mut stem = ascii_from_padded(name_bytes)
  let ext = ascii_from_padded(ext_bytes)
  if raw.length() > 0 && raw[0] == b'\x05' {
    let rest = if stem.length() > 1 {
      stem[1:stem.length()].to_owned()
    } else {
      ""
    }
    stem = "\u{00e5}" + rest
  }
  if ext.length() == 0 {
    stem
  } else {
    stem + "." + ext
  }
}

///|
fn lfn_checksum(short_name : Bytes) -> Int {
  let mut sum = 0
  for i = 0; i < 11; i = i + 1 {
    let rotated = ((sum & 1) << 7) | ((sum & 0xFF) >> 1)
    sum = (rotated + short_name[i].to_int()) & 0xFF
  }
  sum
}

///|
fn lfn_entry_count(name : String) -> Int {
  let chars = name.length()
  (chars + 12) / 13
}

///|
fn utf16_units(name : String) -> Array[Int] {
  let units : Array[Int] = []
  for i = 0; i < name.length(); i = i + 1 {
    let code = name[i].to_int()
    if code <= 0xFFFF {
      units.push(code)
    } else {
      let v = code - 0x10000
      units.push(0xD800 + ((v >> 10) & 0x3FF))
      units.push(0xDC00 + (v & 0x3FF))
    }
  }
  units
}

///|
fn string_from_utf16(units : Array[Int]) -> String {
  let mut text = ""
  let mut i = 0
  while i < units.length() {
    let unit = units[i]
    if unit == 0 {
      break
    }
    if unit >= 0xD800 && unit <= 0xDBFF && i + 1 < units.length() {
      let low = units[i + 1]
      if low >= 0xDC00 && low <= 0xDFFF {
        let code = 0x10000 + (((unit - 0xD800) << 10) | (low - 0xDC00))
        text = text + code.unsafe_to_char().to_string()
        i = i + 2
        continue
      }
    }
    if unit != 0xFFFF {
      text = text + unit.unsafe_to_char().to_string()
    }
    i = i + 1
  }
  text
}

///|
fn short_name_taken(existing : Array[Bytes], candidate : Bytes) -> Bool {
  for i = 0; i < existing.length(); i = i + 1 {
    let mut same = true
    for j = 0; j < 11; j = j + 1 {
      if existing[i][j] != candidate[j] {
        same = false
        break
      }
    }
    if same {
      return true
    }
  }
  false
}

///|
fn make_numeric_tail(stem : String, n : Int) -> String {
  let tail = "~" + n.to_string()
  let keep = 8 - tail.length()
  let mut head = stem
  if head.length() > keep {
    head = head[0:keep].to_owned()
  }
  if head.length() == 0 {
    head = "X"
  }
  head + tail
}

///|
fn allocate_short_name(
  name : String,
  existing : Array[Bytes],
) -> Result[Bytes, FatError] {
  if name == "." {
    return Ok(pack_short_name(".", ""))
  }
  if name == ".." {
    return Ok(pack_short_name("..", ""))
  }
  let (raw_stem, raw_ext) = split_stem_ext(name)
  let (stem, stem_lossy) = sanitize_short_part(raw_stem, 8)
  let (ext, ext_lossy) = if raw_ext.length() == 0 {
    ("", false)
  } else {
    sanitize_short_part(raw_ext, 3)
  }
  let lossy = stem_lossy || ext_lossy || needs_lfn(name)
  if !lossy {
    let candidate = pack_short_name(stem, ext)
    if !short_name_taken(existing, candidate) {
      return Ok(candidate)
    }
  }
  let mut n = 1
  while n < 1000000 {
    let numbered = make_numeric_tail(stem, n)
    let candidate = pack_short_name(numbered, ext)
    if !short_name_taken(existing, candidate) {
      return Ok(candidate)
    }
    n = n + 1
  }
  Err(InvalidName(name))
}

///|
fn join_path(parent : String, name : String) -> String {
  if parent == "/" || parent.length() == 0 {
    "/" + name
  } else if parent[parent.length() - 1].to_int() == 47 {
    parent + name
  } else {
    parent + "/" + name
  }
}
