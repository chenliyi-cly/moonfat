///|
fn u8_at(data : Array[Byte], offset : Int) -> Result[Int, FatError] {
  if offset < 0 || offset >= data.length() {
    Err(Truncated("byte", offset + 1, data.length()))
  } else {
    Ok(data[offset].to_int())
  }
}

///|
fn u16le_at(data : Array[Byte], offset : Int) -> Result[Int, FatError] {
  if offset < 0 || offset + 1 >= data.length() {
    Err(Truncated("u16", offset + 2, data.length()))
  } else {
    Ok(data[offset].to_int() | (data[offset + 1].to_int() << 8))
  }
}

///|
fn u32le_at(data : Array[Byte], offset : Int) -> Result[Int, FatError] {
  if offset < 0 || offset + 3 >= data.length() {
    Err(Truncated("u32", offset + 4, data.length()))
  } else {
    let b0 = data[offset].to_int()
    let b1 = data[offset + 1].to_int()
    let b2 = data[offset + 2].to_int()
    let b3 = data[offset + 3].to_int()
    Ok(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))
  }
}

///|
fn put_u8(
  data : Array[Byte],
  offset : Int,
  value : Int,
) -> Result[Unit, FatError] {
  if offset < 0 || offset >= data.length() {
    Err(Truncated("byte", offset + 1, data.length()))
  } else {
    data[offset] = (value & 0xFF).to_byte()
    Ok(())
  }
}

///|
fn put_u16le(
  data : Array[Byte],
  offset : Int,
  value : Int,
) -> Result[Unit, FatError] {
  if offset < 0 || offset + 1 >= data.length() {
    Err(Truncated("u16", offset + 2, data.length()))
  } else {
    data[offset] = (value & 0xFF).to_byte()
    data[offset + 1] = ((value >> 8) & 0xFF).to_byte()
    Ok(())
  }
}

///|
fn put_u32le(
  data : Array[Byte],
  offset : Int,
  value : Int,
) -> Result[Unit, FatError] {
  if offset < 0 || offset + 3 >= data.length() {
    Err(Truncated("u32", offset + 4, data.length()))
  } else {
    data[offset] = (value & 0xFF).to_byte()
    data[offset + 1] = ((value >> 8) & 0xFF).to_byte()
    data[offset + 2] = ((value >> 16) & 0xFF).to_byte()
    data[offset + 3] = ((value >> 24) & 0xFF).to_byte()
    Ok(())
  }
}

///|
fn slice_bytes(
  data : Array[Byte],
  start : Int,
  length : Int,
) -> Result[Bytes, FatError] {
  if start < 0 || length < 0 || start + length > data.length() {
    Err(Truncated("slice", start + length, data.length()))
  } else {
    Ok(Bytes::makei(length, i => data[start + i]))
  }
}

///|
fn blit_bytes(
  data : Array[Byte],
  start : Int,
  source : Bytes,
) -> Result[Unit, FatError] {
  if start < 0 || start + source.length() > data.length() {
    Err(Truncated("blit", start + source.length(), data.length()))
  } else {
    for i = 0; i < source.length(); i = i + 1 {
      data[start + i] = source[i]
    }
    Ok(())
  }
}

///|
fn fill_bytes(
  data : Array[Byte],
  start : Int,
  length : Int,
  value : Byte,
) -> Result[Unit, FatError] {
  if start < 0 || length < 0 || start + length > data.length() {
    Err(Truncated("fill", start + length, data.length()))
  } else {
    for i = 0; i < length; i = i + 1 {
      data[start + i] = value
    }
    Ok(())
  }
}

///|
fn ascii_pad11(text : String) -> Result[Bytes, FatError] {
  let out = Array::make(11, b' ')
  let mut i = 0
  while i < text.length() && i < 11 {
    let code = text[i].to_int()
    if code < 32 || code > 126 {
      return Err(InvalidName(text))
    }
    out[i] = code.to_byte()
    i = i + 1
  }
  Ok(Bytes::from_array(out))
}

///|
fn ascii_from_padded(data : Bytes) -> String {
  let mut end = data.length()
  while end > 0 && data[end - 1] == b' ' {
    end = end - 1
  }
  let mut text = ""
  for i = 0; i < end; i = i + 1 {
    text = text + data[i].to_int().unsafe_to_char().to_string()
  }
  text
}

///|
fn hex_digit(value : Int) -> Char {
  if value < 10 {
    (48 + value).unsafe_to_char()
  } else {
    (87 + value).unsafe_to_char()
  }
}

///|
pub fn hex_encode(data : Bytes) -> String {
  let mut text = ""
  for i = 0; i < data.length(); i = i + 1 {
    let value = data[i].to_int()
    text = text + hex_digit((value >> 4) & 0x0F).to_string()
    text = text + hex_digit(value & 0x0F).to_string()
  }
  text
}

///|
fn power_of_two(value : Int) -> Bool {
  value > 0 && (value & (value - 1)) == 0
}
