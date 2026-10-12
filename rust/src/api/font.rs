//! 系统已安装字体家族枚举（字体设置页「系统已装字体」档的选择器数据源）。
//! font-kit 按目标平台走原生字体库：macOS/iOS = CoreText，Windows = DirectWrite，
//! Linux = fontconfig，Android = 扫描字体目录。

#[cfg(not(target_os = "android"))]
use font_kit::source::SystemSource;

/// 枚举系统已安装字体的家族名，去重后按（不区分大小写的）字典序返回。
/// 枚举失败（如无字体环境）返回空表而不报错 —— 调用方回退手动输入。
#[cfg(not(target_os = "android"))]
pub fn list_system_font_families() -> Vec<String> {
    let source = SystemSource::new();
    let mut families = match source.all_families() {
        Ok(families) => families,
        Err(_) => return Vec::new(),
    };
    families.retain(|name| !name.trim().is_empty());
    families.sort_by(|a, b| a.to_lowercase().cmp(&b.to_lowercase()));
    families.dedup_by(|a, b| a.to_lowercase() == b.to_lowercase());
    families
}

/// 安卓：扫描系统字体目录，取文件名当家族名。
///
/// 这里是 `font-kit` 注释里写明的那条路（Android = 扫描字体目录）：安卓没有 fontconfig，
/// 而 bionic 的字库位置固定，扫目录就能拿到设备实际可用的字体名；
/// 拿不到目录时返回空表（与上面「枚举失败返回空表」的口径一致，不编造假数据）。
#[cfg(target_os = "android")]
pub fn list_system_font_families() -> Vec<String> {
    const FONT_DIRS: [&str; 3] = ["/system/fonts", "/product/fonts", "/data/fonts"];
    const FONT_EXTS: [&str; 4] = ["ttf", "otf", "ttc", "otc"];

    let mut families: Vec<String> = Vec::new();
    for dir in FONT_DIRS {
        let Ok(entries) = std::fs::read_dir(dir) else {
            continue;
        };
        for entry in entries.flattened() {
            let path = entry.path();
            let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            let Some((stem, ext)) = name.rsplit_once('.') else {
                continue;
            };
            if !FONT_EXTS.contains(&ext.to_ascii_lowercase().as_str()) {
                continue;
            }
            if !stem.trim().is_empty() {
                families.push(stem.to_string());
            }
        }
    }
    families.sort_by(|a, b| a.to_lowercase().cmp(&b.to_lowercase()));
    families.dedup_by(|a, b| a.to_lowercase() == b.to_lowercase());
    families
}
