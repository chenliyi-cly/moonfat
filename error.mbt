///|
/// FAT12/16/32 codec errors with stable diagnostic codes.
pub(all) enum FatError {
  Truncated(String, Int, Int)
  InvalidBoot(String)
  Unsupported(String)
  BadCluster(Int)
  ChainLoop(Int)
  NotFound(String)
  AlreadyExists(String)
  NotDirectory(String)
  IsDirectory(String)
  DirectoryNotEmpty(String)
  NoSpace
  InvalidName(String)
  Corrupt(String)
  InvalidPath(String)
  SlotExhausted
} derive(Eq, Debug)

///|
pub fn FatError::code(self : FatError) -> String {
  match self {
    Truncated(_) => "FAT001"
    InvalidBoot(_) => "FAT002"
    Unsupported(_) => "FAT003"
    BadCluster(_) => "FAT004"
    ChainLoop(_) => "FAT005"
    NotFound(_) => "FAT006"
    AlreadyExists(_) => "FAT007"
    NotDirectory(_) => "FAT008"
    IsDirectory(_) => "FAT009"
    DirectoryNotEmpty(_) => "FAT010"
    NoSpace => "FAT011"
    InvalidName(_) => "FAT012"
    Corrupt(_) => "FAT013"
    InvalidPath(_) => "FAT014"
    SlotExhausted => "FAT015"
  }
}

///|
pub fn FatError::message(self : FatError) -> String {
  match self {
    Truncated(section, expected, actual) =>
      "truncated \{section}: need \{expected} bytes, have \{actual}"
    InvalidBoot(reason) => "invalid boot sector: \{reason}"
    Unsupported(reason) => "unsupported volume: \{reason}"
    BadCluster(cluster) => "cluster \{cluster} is bad or reserved"
    ChainLoop(cluster) => "cluster chain loops at \{cluster}"
    NotFound(path) => "path not found: \{path}"
    AlreadyExists(path) => "path already exists: \{path}"
    NotDirectory(path) => "not a directory: \{path}"
    IsDirectory(path) => "path is a directory: \{path}"
    DirectoryNotEmpty(path) => "directory is not empty: \{path}"
    NoSpace => "volume is out of free clusters or directory slots"
    InvalidName(name) => "invalid file name: \{name}"
    Corrupt(reason) => "volume is corrupt: \{reason}"
    InvalidPath(path) => "invalid path: \{path}"
    SlotExhausted => "directory has no consecutive free slots"
  }
}

///|
pub fn FatError::render(self : FatError) -> String {
  "\{self.code()}: \{self.message()}"
}
