//! 图像旋转与归一化 UV 空间几何变换。
//!
//! 提供纯 Rust、无 UI 依赖的 90° 步进旋转枚举及坐标映射函数。
//! 对应 mImageViewer 的 `rotation_db::Rotation` 与 `displayed_image_transform::{forward_uv, inverse_uv}`。

/// 顺时针旋转角度。
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum Rotation {
    #[default]
    None, // 0°
    Cw90,  // 顺时针 90°
    Cw180, // 顺时针 180°
    Cw270, // 顺时针 270° (即逆时针 90°)
}

impl Rotation {
    /// 从任意整数角度（度）规约为四向旋转。
    pub fn from_degrees(deg: i32) -> Self {
        match deg.rem_euclid(360) {
            90 => Self::Cw90,
            180 => Self::Cw180,
            270 => Self::Cw270,
            _ => Self::None,
        }
    }

    /// 返回对应的顺时针度数 (0, 90, 180, 270)。
    pub fn degrees(self) -> i32 {
        match self {
            Self::None => 0,
            Self::Cw90 => 90,
            Self::Cw180 => 180,
            Self::Cw270 => 270,
        }
    }

    /// 顺时针旋转 90°。
    pub fn rotate_cw(self) -> Self {
        match self {
            Self::None => Self::Cw90,
            Self::Cw90 => Self::Cw180,
            Self::Cw180 => Self::Cw270,
            Self::Cw270 => Self::None,
        }
    }

    /// 逆时针旋转 90°。
    pub fn rotate_ccw(self) -> Self {
        match self {
            Self::None => Self::Cw270,
            Self::Cw90 => Self::None,
            Self::Cw180 => Self::Cw90,
            Self::Cw270 => Self::Cw180,
        }
    }

    /// 是否无旋转。
    pub fn is_none(self) -> bool {
        matches!(self, Self::None)
    }
}

/// 将显示空间（已旋转）的归一化 UV 坐标逆映射回原始图像空间。
///
/// 用于在有旋转状态下，将屏幕上选取的子矩形换算回源图。
pub fn inverse_uv(rotation: Rotation, u: f32, v: f32) -> (f32, f32) {
    match rotation {
        Rotation::None => (u, v),
        Rotation::Cw90 => (v, 1.0 - u),
        Rotation::Cw180 => (1.0 - u, 1.0 - v),
        Rotation::Cw270 => (1.0 - v, u),
    }
}

/// 将原始图像空间的归一化 UV 坐标正向映射到显示空间（已旋转）。
pub fn forward_uv(rotation: Rotation, u: f32, v: f32) -> (f32, f32) {
    match rotation {
        Rotation::None => (u, v),
        Rotation::Cw90 => (1.0 - v, u),
        Rotation::Cw180 => (1.0 - u, 1.0 - v),
        Rotation::Cw270 => (v, 1.0 - u),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn degrees_roundtrip_and_steps() {
        assert_eq!(Rotation::from_degrees(0), Rotation::None);
        assert_eq!(Rotation::from_degrees(90), Rotation::Cw90);
        assert_eq!(Rotation::from_degrees(180), Rotation::Cw180);
        assert_eq!(Rotation::from_degrees(270), Rotation::Cw270);
        assert_eq!(Rotation::from_degrees(360), Rotation::None);
        assert_eq!(Rotation::from_degrees(-90), Rotation::Cw270);

        assert_eq!(Rotation::None.degrees(), 0);
        assert_eq!(Rotation::Cw90.degrees(), 90);
        assert_eq!(Rotation::Cw180.degrees(), 180);
        assert_eq!(Rotation::Cw270.degrees(), 270);

        assert_eq!(Rotation::None.rotate_cw(), Rotation::Cw90);
        assert_eq!(Rotation::Cw270.rotate_cw(), Rotation::None);
        assert_eq!(Rotation::None.rotate_ccw(), Rotation::Cw270);
        assert_eq!(Rotation::Cw90.rotate_ccw(), Rotation::None);
    }

    #[test]
    fn forward_and_inverse_uv_are_exact_inverses() {
        let test_points = [(0.0, 0.0), (1.0, 1.0), (0.25, 0.75), (0.5, 0.5), (0.1, 0.9)];
        let rotations = [
            Rotation::None,
            Rotation::Cw90,
            Rotation::Cw180,
            Rotation::Cw270,
        ];

        for rot in rotations {
            for (u, v) in test_points {
                let (disp_u, disp_v) = forward_uv(rot, u, v);
                let (back_u, back_v) = inverse_uv(rot, disp_u, disp_v);
                assert!(
                    (back_u - u).abs() < 1e-6 && (back_v - v).abs() < 1e-6,
                    "Failed for rot={rot:?}, u={u}, v={v} -> back=({back_u}, {back_v})"
                );

                let (inv_u, inv_v) = inverse_uv(rot, u, v);
                let (fwd_u, fwd_v) = forward_uv(rot, inv_u, inv_v);
                assert!(
                    (fwd_u - u).abs() < 1e-6 && (fwd_v - v).abs() < 1e-6,
                    "Failed inverse->forward for rot={rot:?}, u={u}, v={v} -> back=({fwd_u}, {fwd_v})"
                );
            }
        }
    }
}
