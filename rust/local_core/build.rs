//! 补上 `unrar_sys` 在 Windows 上少声明的系统库。
//!
//! `unrar_sys` 会把整个 UnRAR C++ 源一起编译进来，其中
//! `pathfn.cpp` / `system.cpp` / `extinfo.cpp` / `crypt.cpp` 直接调用注册表
//! (`RegOpenKeyExW` / `RegQueryValueExW` / `RegCloseKey`)、进程令牌
//! (`OpenProcessToken` / `AdjustTokenPrivileges` / `AllocateAndInitializeSid` …)、
//! 文件 ACL (`SetFileSecurityW`) 与 CryptoAPI (`CryptGenRandom` …)，
//! 这些符号全部住在 **advapi32**。
//!
//! 上游 `unrar_sys` 的 build script 没有声明它（它假设调用方自己会带），
//! 于是当 `unrar` 只是被一个「没有依赖 `windows` crate 的调用方」链接时，
//! 会在链接期炸出 13 个 `__imp_*` 未解析符号：
//!
//! ```text
//! error LNK2019: 无法解析的外部符号 __imp_RegCloseKey …
//! error LNK1120: 13 个无法解析的外部命令
//! ```
//!
//! mImageViewer 没暴露这个问题，是因为它自己依赖了 `windows` crate 的
//! `Win32_Security` / `Win32_System_Registry` 模块，间接把 advapi32 带了进来。
//! Rossi 的本地核心刻意不依赖 `windows` crate，所以在这里显式补上。
//!
//! 注意 `cargo:rustc-link-lib` 是会被记录进 crate 元数据并**向上传播**的，
//! 所以这一条同时修好了本 crate 的 test/bin 目标与将来 windcore 的 cdylib。

fn main() {
    if std::env::var("CARGO_CFG_WINDOWS").is_ok() {
        println!("cargo:rustc-link-lib=advapi32");
    }
    println!("cargo:rerun-if-changed=build.rs");
}
