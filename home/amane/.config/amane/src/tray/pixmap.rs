use std::fs::{self, DirBuilder};
use std::io;
use std::os::unix::fs::DirBuilderExt;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

// Older Amane builds accept image paths only. Store the bitmap once per icon change.
pub(super) struct PixmapFile {
    dir: PathBuf,
    pub path: PathBuf,
}

impl PixmapFile {
    pub(super) fn new(width: u32, height: u32, rgba: &[u8]) -> io::Result<Self> {
        static NEXT: AtomicU64 = AtomicU64::new(0);
        let root = std::env::var_os("XDG_RUNTIME_DIR")
            .filter(|dir| !dir.is_empty())
            .map_or_else(std::env::temp_dir, PathBuf::from);
        let time = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let next = NEXT.fetch_add(1, Ordering::Relaxed);
        let dir = root.join(format!("amane-tray-{}-{time:x}-{next}", std::process::id()));
        DirBuilder::new().mode(0o700).create(&dir)?;
        let file = Self {
            path: dir.join("icon.png"),
            dir,
        };
        fs::write(&file.path, encode(width, height, rgba))?;
        Ok(file)
    }
}

impl Drop for PixmapFile {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
        let _ = fs::remove_dir(&self.dir);
    }
}

fn encode(width: u32, height: u32, rgba: &[u8]) -> Vec<u8> {
    let stride = width as usize * 4;
    let mut scanlines = Vec::with_capacity(rgba.len() + height as usize);
    for row in rgba.chunks_exact(stride) {
        scanlines.push(0); // PNG row filter: none.
        scanlines.extend_from_slice(row);
    }

    // Zlib with stored DEFLATE blocks: no compressor dependency for these tiny icons.
    let mut zlib = vec![0x78, 0x01];
    let mut blocks = scanlines.chunks(u16::MAX as usize).peekable();
    while let Some(block) = blocks.next() {
        let len = block.len() as u16;
        zlib.push(u8::from(blocks.peek().is_none()));
        zlib.extend(len.to_le_bytes());
        zlib.extend((!len).to_le_bytes());
        zlib.extend(block);
    }
    let (a, b) = scanlines.iter().fold((1u32, 0u32), |(a, b), &byte| {
        let a = (a + u32::from(byte)) % 65_521;
        (a, (a + b) % 65_521)
    });
    zlib.extend(((b << 16) | a).to_be_bytes());

    let mut png = b"\x89PNG\r\n\x1a\n".to_vec();
    let mut header = width.to_be_bytes().to_vec();
    header.extend(height.to_be_bytes());
    header.extend([8, 6, 0, 0, 0]); // 8-bit RGBA.
    chunk(&mut png, b"IHDR", &header);
    chunk(&mut png, b"IDAT", &zlib);
    chunk(&mut png, b"IEND", &[]);
    png
}

fn chunk(png: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
    png.extend((data.len() as u32).to_be_bytes());
    let start = png.len();
    png.extend(kind);
    png.extend(data);
    let sum = png[start..].iter().fold(u32::MAX, |crc, &byte| {
        (0..8).fold(crc ^ u32::from(byte), |crc, _| {
            (crc >> 1) ^ (0xedb8_8320 & 0u32.wrapping_sub(crc & 1))
        })
    });
    png.extend((!sum).to_be_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_and_retires_a_png() {
        let file = PixmapFile::new(1, 1, &[0x12, 0x34, 0x56, 0x80]).unwrap();
        let path = file.path.clone();
        let png = fs::read(&path).unwrap();
        assert_eq!(&png[..8], b"\x89PNG\r\n\x1a\n");
        assert_eq!(&png[29..33], &[0x1f, 0x15, 0xc4, 0x89]); // CRC of a 1×1 RGBA IHDR.
        assert_eq!(&png[48..53], &[0, 0x12, 0x34, 0x56, 0x80]);
        drop(file);
        assert!(!path.exists());
    }
}
