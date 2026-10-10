//! 系统已安装字体家族枚举（字体设置页「系统已装字体」档的选择器数据源）。
//! font-kit 按目标平台走原生字体库：macOS/iOS = CoreText，Windows = DirectWrite，
//! Linux = fontconfig，Android = 扫描字体目录。

use font_kit::source::SystemSource;

/// 枚举系统已安装字体的家族名，去重后按（不区分大小写的）字典序返回。
/// 枚举失败（如无字体环境）返回空表而不报错 —— 调用方回退手动输入。
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
