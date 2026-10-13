//! 直接复用 mImageViewer 旋转类型与 UV 几何函数切片（MIT）。
//! 不引入其旋转数据库和 egui 布局；Rossi 只补 Default。
include!(concat!(env!("OUT_DIR"), "/rotation.rs"));
include!(concat!(env!("OUT_DIR"), "/rotation_uv.rs"));
impl Default for Rotation {
    fn default() -> Self {
        Self::None
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
