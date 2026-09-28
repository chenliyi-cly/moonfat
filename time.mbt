///|
/// DOS directory timestamp used when writing entries.
pub(all) struct DosTime {
  year : Int
  month : Int
  day : Int
  hour : Int
  minute : Int
  second : Int
} derive(Eq, Debug)

///|
pub fn default_dos_time() -> DosTime {
  { year: 2026, month: 9, day: 1, hour: 12, minute: 0, second: 0 }
}

///|
fn pack_dos_date(time : DosTime) -> Int {
  let year = time.year - 1980
  ((year & 0x7F) << 9) | ((time.month & 0x0F) << 5) | (time.day & 0x1F)
}

///|
fn pack_dos_time(time : DosTime) -> Int {
  ((time.hour & 0x1F) << 11) |
  ((time.minute & 0x3F) << 5) |
  ((time.second / 2) & 0x1F)
}

///|
fn unpack_dos_stamp(date : Int, time : Int) -> DosTime {
  {
    year: 1980 + ((date >> 9) & 0x7F),
    month: (date >> 5) & 0x0F,
    day: date & 0x1F,
    hour: (time >> 11) & 0x1F,
    minute: (time >> 5) & 0x3F,
    second: (time & 0x1F) * 2,
  }
}
