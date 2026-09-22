// 从 file_manager.rs 整块原样搬出；除补必要的可见性前缀外未改一个字符。
use super::*;

pub(super) fn directory_title(path: &Path) -> String {
    path.file_name()
        .filter(|name| !name.is_empty())
        .unwrap_or(path.as_os_str())
        .to_string_lossy()
        .into_owned()
}

pub(super) fn default_directory() -> Option<PathBuf> {
    crate::file_tree::get_available_roots()
        .into_iter()
        .find_map(|root| normalize_initial_directory(PathBuf::from(root.path)))
}

pub(super) fn same_path(a: &Path, b: &Path) -> bool {
    crate::folder_tree::path_eq(a, b)
}

pub(super) fn natural_name_cmp(left: &str, right: &str) -> std::cmp::Ordering {
    crate::filename_sort::SortNameKey::with_natural(left)
        .compare_natural(&crate::filename_sort::SortNameKey::with_natural(right))
}

/// splitmix64 终混。只用于把种子与名称摊平，不承担任何密码学职责。
pub(super) fn mix64(mut value: u64) -> u64 {
    value = value.wrapping_add(0x9E37_79B9_7F4A_7C15);
    value = (value ^ (value >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    value = (value ^ (value >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    value ^ (value >> 31)
}

/// 每个名称在给定种子下得到固定的洗牌键，所以同一目录的快照之间顺序不会跳动。
pub(super) fn shuffle_key(seed: u64, name: &str) -> u64 {
    let mut hash = 0xCBF2_9CE4_8422_2325u64;
    for byte in name.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x0000_0100_0000_01B3);
    }
    mix64(seed ^ mix64(hash))
}

pub(super) fn fresh_shuffle_seed() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_nanos() as u64)
        // 时间不可用时退回固定种子：顺序不随机仍是合法排序，不能因此 panic。
        .unwrap_or(0x5EED_5EED)
        .max(1)
}

pub(super) fn extension_cmp(left: &FileTreeNode, right: &FileTreeNode) -> std::cmp::Ordering {
    let extension = |node: &FileTreeNode| {
        Path::new(&node.path)
            .extension()
            .and_then(|value| value.to_str())
            .map(|value| value.to_ascii_lowercase())
            .unwrap_or_default()
    };
    extension(left).cmp(&extension(right))
}

pub(super) fn visit_key(path: &Path) -> String {
    crate::fs_entry::directory_visit_key(path)
}
