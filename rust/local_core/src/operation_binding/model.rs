//! Rossi 使用公共输入协议；业务词汇留在 vocabulary。
pub use operation_binding_core::model::*;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::operation_binding::vocabulary::{InputContext, ReaderViewArea};

    #[test]
    fn editor_rejects_duplicate_ids_and_more_than_seven_follow_ups() {
        let mut row: InputBinding = serde_json::from_str(
            r#"{"id":"custom","action":"reader.next-page","context":"reader","enabled":true,
            "input":{"device":"keyboard","code":"KeyN"}}"#,
        )
        .unwrap();
        row.follow_up_actions = vec!["reader.zoom-in".into(); 7];
        assert!(bindings_are_valid(&[row.clone()]));
        assert!(!bindings_are_valid(&[row.clone(), row.clone()]));
        row.follow_up_actions.push("reader.zoom-out".into());
        assert!(!bindings_are_valid(&[row]));
    }

    #[test]
    fn editor_rejects_invalid_device_parameters() {
        for input in [
            r#"{"device":"touch","gesture":"swipe-left","fingers":0}"#,
            r#"{"device":"touch","gesture":"swipe-left","fingers":4}"#,
            r#"{"device":"mouse-gesture","button":2,"directions":[],"trigger":"instant"}"#,
            r#"{"device":"keyboard","code":" "}"#,
            r#"{"device":"gamepad","button":32}"#,
        ] {
            let row: InputBinding = serde_json::from_str(&format!(
                r#"{{"id":"custom","action":"reader.next-page","context":"reader","enabled":true,"input":{input}}}"#
            )).unwrap();
            assert!(!bindings_are_valid(&[row]), "{input}");
        }
    }

    #[test]
    fn descriptor_json_shape_matches_neoview() {
        // 形状取自 neoview 的导出（`device` 作 tag、字段 camelCase）。
        let keyboard: InputDescriptor =
            serde_json::from_str(r#"{"device":"keyboard","code":"ArrowLeft"}"#).unwrap();
        assert_eq!(
            keyboard,
            InputDescriptor::Keyboard {
                code: "ArrowLeft".into(),
                trigger: KeyTrigger::Down,
                ctrl: false,
                alt: false,
                shift: false,
                meta: false,
            }
        );

        let area: InputDescriptor = serde_json::from_str(
            r#"{"device":"mouse","area":"middle-left","button":0,"action":"click"}"#,
        )
        .unwrap();
        assert_eq!(
            area,
            InputDescriptor::Mouse {
                area: Some(ReaderViewArea::MiddleLeft.as_str().into()),
                button: 0,
                action: PointerAction::Click,
            }
        );

        // 后四类必须**可解析**（导入 neoview 的包不许把用户的手柄/轮盘绑定洗掉）。
        for raw in [
            r#"{"device":"gamepad","button":3}"#,
            r#"{"device":"mouse-gesture","button":2,"directions":["left","up"],"trigger":"instant"}"#,
            r#"{"device":"radial","menuId":"default","itemId":"radial-next-page"}"#,
            r#"{"device":"command","command":"file-card.trash-current"}"#,
        ] {
            let parsed: InputDescriptor = serde_json::from_str(raw)
                .unwrap_or_else(|error| panic!("这一类的 descriptor 必须能解析（{raw}）：{error}"));
            // 往返不丢信息。
            let round_tripped: InputDescriptor =
                serde_json::from_str(&serde_json::to_string(&parsed).unwrap()).unwrap();
            assert_eq!(round_tripped, parsed);
        }
    }

    #[test]
    fn binding_actions_put_primary_first() {
        let binding = InputBinding {
            id: "x".into(),
            action: "reader.next-page".into(),
            follow_up_actions: vec!["reader.page-right".into()],
            context: InputContext::Reader.as_str().into(),
            enabled: true,
            ignore_repeat: false,
            input: InputDescriptor::Keyboard {
                code: "ArrowRight".into(),
                trigger: KeyTrigger::Down,
                ctrl: false,
                alt: false,
                shift: false,
                meta: false,
            },
        };
        assert_eq!(
            binding.actions(),
            vec!["reader.next-page", "reader.page-right"]
        );
    }

    #[test]
    fn config_round_trips_every_descriptor_class() {
        // 一次「导入 → 存回」不许洗掉任何一条 —— 尤其是 v0.1 运行时**不产生**的那四类
        // （手柄 / 轨迹手势 / 轮盘 / 命令）：它们只可解析、不可编辑，但必须原样留着。
        const IMPORTED: &str = r#"{
          "format": "operation-bindings",
          "format_version": 2,
          "bindings": [
            {"id":"k1","action":"reader.page-right","context":"reader","enabled":true,
             "input":{"device":"keyboard","code":"ArrowRight","ctrl":true}},
            {"id":"k2","action":"reader.next-page","context":"global","enabled":false,
             "ignoreRepeat":true,"followUpActions":["reader.toggle-controls"],
             "input":{"device":"wheel","direction":"down","shift":true}},
            {"id":"g1","action":"reader.zoom-in","context":"reader","enabled":true,
             "input":{"device":"gamepad","button":3}},
            {"id":"mg1","action":"reader.reset-view","context":"reader","enabled":true,
             "input":{"device":"mouse-gesture","button":2,"directions":["left","up"],"trigger":"hold"}},
            {"id":"r1","action":"reader.last-page","context":"reader","enabled":true,
             "input":{"device":"radial","menuId":"default","itemId":"radial-next-page"}},
            {"id":"c1","action":"reader.open-settings","context":"shell","enabled":true,
             "input":{"device":"command","command":"file-card.trash-current"}},
            {"id":"a1","action":"reader.page-left","context":"reader","enabled":true,
             "input":{"device":"mouse","area":"middle-left","button":0,"action":"click"}},
            {"id":"t1","action":"reader.fullscreen","context":"reader","enabled":true,
             "input":{"device":"touch","gesture":"swipe-left","fingers":2}},
            {"id":"m1","action":"reader.actual-size","context":"modal","enabled":true,
             "input":{"device":"mouse","button":1,"action":"double-click"}}
          ]
        }"#;

        let parsed: InputBindingsConfig = serde_json::from_str(IMPORTED).unwrap();
        assert_eq!(parsed.bindings.len(), 9);
        // 追加动作与开关都活着（丢了就是「导入把用户的配置洗掉了」）。
        let with_follow_up = parsed
            .bindings
            .iter()
            .find(|binding| binding.id == "k2")
            .unwrap();
        assert!(!with_follow_up.enabled);
        assert!(with_follow_up.ignore_repeat);
        assert_eq!(
            with_follow_up.follow_up_actions,
            vec!["reader.toggle-controls"]
        );

        let written = serde_json::to_string(&parsed).unwrap();
        let again: InputBindingsConfig = serde_json::from_str(&written).unwrap();
        assert_eq!(again, parsed, "绑定包往返必须逐字段等价");

        // 裸数组也收（引擎对外的 FRB 形状就是数组，预设导出即数组）。
        let bare: Vec<InputBinding> =
            serde_json::from_str(&serde_json::to_string(&parsed.bindings).unwrap()).unwrap();
        assert_eq!(bare, parsed.bindings);
    }
}
