//! Neo 默认配置。数据取自 Xiranite 的
//! `packages/nodes/neoview/src/domain/input/ReaderInputBindings.ts`
//! `DEFAULT_READER_INPUT_BINDINGS`，仅取九宫格、滚轮、键盘、鼠标四类。
//! 保留上游的 id、动作、上下文和空白区域；轮盘槽位沿用本仓轮盘文档。

use serde_json::Value;

use super::{InputBinding, model, preset, radial, resolve};

pub fn input_bindings() -> Vec<InputBinding> {
    serde_json::from_str(include_str!("neo_defaults.json")).expect("Neo 默认绑定必须合法")
}

pub fn bindings() -> Vec<InputBinding> {
    let mut bindings = input_bindings();
    bindings.extend(radial::preset_bindings(radial::DEFAULT_RADIAL_MENU_ID));
    bindings
}

/// 只升级完整、未改动的旧默认输入表。空表、删过行、改键、禁用或追加动作都属于自定义。
/// 轮盘绑定独立保留原始 JSON，避免丢掉用户的槽位、追加动作和扩展字段。
pub fn upgrade_legacy_defaults(rows: &[Value]) -> Option<Vec<Value>> {
    let mut old = Vec::new();
    let mut radial_rows = Vec::new();
    for row in rows {
        let binding: InputBinding = serde_json::from_value(row.clone()).ok()?;
        if matches!(binding.input, super::InputDescriptor::Radial { .. }) {
            radial_rows.push(row.clone());
        } else {
            // 反序列化会忽略未知字段；有扩展/时序参数时不能误认成出厂行。
            if !known_fields_only(row, &serde_json::to_value(&binding).ok()?) {
                return None;
            }
            old.push(binding);
        }
    }
    old.sort_by(|a, b| a.id.cmp(&b.id));
    let untouched = [preset::TapPreset::RightHand, preset::TapPreset::LeftHand]
        .into_iter()
        .any(|tap| {
            preset::legacy_key_preset_versions()
                .into_iter()
                .any(|mut expected| {
                    expected.extend(preset::tap_preset_bindings(tap));
                    expected.sort_by(|a, b| a.id.cmp(&b.id));
                    old == expected
                })
        });
    if !untouched {
        return None;
    }
    let mut upgraded: Vec<Value> = input_bindings()
        .into_iter()
        .map(|binding| serde_json::to_value(binding).expect("默认绑定必须可序列化"))
        .collect();
    upgraded.extend(radial_rows);
    let parsed: Vec<InputBinding> = serde_json::from_value(Value::Array(upgraded.clone())).ok()?;
    (model::bindings_are_valid(&parsed) && resolve::conflicts(&parsed).is_empty())
        .then_some(upgraded)
}

fn known_fields_only(raw: &Value, normalized: &Value) -> bool {
    match (raw, normalized) {
        (Value::Object(raw), Value::Object(normalized)) => raw.iter().all(|(key, value)| {
            normalized
                .get(key)
                .is_some_and(|expected| known_fields_only(value, expected))
        }),
        _ => true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::operation_binding::{InputContext, vocabulary::action};
    use serde_json::json;

    fn action_for(input: Value, contexts: &[InputContext]) -> Option<String> {
        let input = serde_json::from_value(input).unwrap();
        resolve::resolve(&bindings(), &input, contexts).map(|row| row.action.clone())
    }

    fn legacy(tap: preset::TapPreset) -> Vec<Value> {
        preset::key_preset_bindings()
            .into_iter()
            .chain(preset::tap_preset_bindings(tap))
            .chain(radial::preset_bindings(radial::DEFAULT_RADIAL_MENU_ID))
            .map(|row| serde_json::to_value(row).unwrap())
            .collect()
    }

    #[test]
    fn neo_grid_keeps_blank_cells_and_video_overrides() {
        let click = |area| json!({"device":"area","area":area,"button":0,"action":"click"});
        for (area, expected) in [
            ("top-left", None),
            ("top-center", Some(action::PREVIOUS_BOOK)),
            ("top-right", None),
            ("middle-left", Some(action::PAGE_LEFT)),
            ("middle-center", None),
            ("middle-right", Some(action::PAGE_RIGHT)),
            ("bottom-left", Some(action::PAGE_RIGHT)),
            ("bottom-center", Some(action::NEXT_BOOK)),
            ("bottom-right", Some(action::PAGE_RIGHT)),
        ] {
            assert_eq!(
                action_for(click(area), &[InputContext::Reader]).as_deref(),
                expected,
                "{area}"
            );
        }
        for (area, expected) in [
            ("middle-left", action::VIDEO_SEEK_BACKWARD),
            ("middle-center", action::VIDEO_PLAY_PAUSE),
            ("middle-right", action::VIDEO_SEEK_FORWARD),
        ] {
            assert_eq!(
                action_for(click(area), &[InputContext::Reader, InputContext::Video]).as_deref(),
                Some(expected)
            );
        }
    }

    #[test]
    fn neo_wheel_keys_and_mouse_resolve_with_context_isolation() {
        for (input, expected) in [
            (
                json!({"device":"wheel","direction":"down"}),
                action::PAGE_LEFT,
            ),
            (
                json!({"device":"wheel","direction":"up"}),
                action::PAGE_RIGHT,
            ),
            (
                json!({"device":"keyboard","code":"KeyW"}),
                action::PREVIOUS_BOOK,
            ),
            (
                json!({"device":"keyboard","code":"ArrowUp"}),
                action::PREVIOUS_BOOK,
            ),
            (
                json!({"device":"keyboard","code":"KeyS"}),
                action::NEXT_BOOK,
            ),
            (
                json!({"device":"keyboard","code":"ArrowDown"}),
                action::NEXT_BOOK,
            ),
            (
                json!({"device":"keyboard","code":"KeyL"}),
                action::TOGGLE_LIBRARY,
            ),
            (
                json!({"device":"keyboard","code":"KeyR"}),
                action::TOGGLE_READING_DIRECTION,
            ),
            (
                json!({"device":"keyboard","code":"Enter"}),
                action::OPEN_RADIAL_MENU,
            ),
            (
                json!({"device":"keyboard","code":"Space"}),
                action::CONFIRM_RADIAL_MENU,
            ),
            (
                json!({"device":"mouse","button":2,"action":"press"}),
                action::OPEN_RADIAL_MENU,
            ),
        ] {
            assert_eq!(
                action_for(input, &[InputContext::Reader]).as_deref(),
                Some(expected)
            );
        }
        assert_eq!(
            action_for(
                json!({"device":"wheel","direction":"down","ctrl":true}),
                &[InputContext::Reader]
            ),
            None
        );
        for context in [
            InputContext::Editor,
            InputContext::Modal,
            InputContext::Shell,
        ] {
            assert_eq!(
                action_for(json!({"device":"keyboard","code":"KeyA"}), &[context]),
                None
            );
        }
        let defaults = bindings();
        assert!(model::bindings_are_valid(&defaults));
        assert!(resolve::conflicts(&defaults).is_empty());
        for row in &defaults {
            assert!(
                super::super::vocabulary::action_definition(&row.action).is_some(),
                "{} must be visible in the editor",
                row.action
            );
        }
    }

    #[test]
    fn upgrade_is_idempotent_and_preserves_custom_radial_json() {
        for tap in [preset::TapPreset::RightHand, preset::TapPreset::LeftHand] {
            let mut old = legacy(tap);
            let radial = old.last_mut().unwrap();
            radial["followUpActions"] = json!([action::ZOOM_IN]);
            radial["extension"] = json!({"preserve": true});
            let radial = radial.clone();
            old.reverse(); // 行顺序不影响是否为旧默认值。
            let upgraded = upgrade_legacy_defaults(&old).unwrap();
            assert!(upgraded.contains(&radial));
            assert!(upgraded.iter().any(|row| row["input"]["device"] == "wheel"));
            assert!(upgrade_legacy_defaults(&upgraded).is_none());
        }
    }

    #[test]
    fn customized_inputs_are_never_overwritten() {
        let old = legacy(preset::TapPreset::RightHand);
        for changed in [
            json!({"enabled":false}),
            json!({"action":action::LAST_PAGE}),
            json!({"ignoreRepeat":true}),
            json!({"followUpActions":[action::ZOOM_IN]}),
            json!({"customExtension":true}),
        ] {
            let mut rows = old.clone();
            rows[0]
                .as_object_mut()
                .unwrap()
                .extend(changed.as_object().unwrap().clone());
            assert!(upgrade_legacy_defaults(&rows).is_none());
        }
        let mut timed = old.clone();
        timed[0]["input"]["durationMs"] = json!(900);
        assert!(upgrade_legacy_defaults(&timed).is_none());
        let mut deleted = old.clone();
        deleted.remove(0);
        assert!(upgrade_legacy_defaults(&deleted).is_none());
        let mut added = old.clone();
        let mut row = added[0].clone();
        row["id"] = json!("custom-key");
        added.push(row);
        assert!(upgrade_legacy_defaults(&added).is_none());
        assert!(upgrade_legacy_defaults(&[]).is_none());
    }

    #[test]
    fn recognizes_complete_historical_versions_before_zoom_and_video_defaults() {
        for version in preset::legacy_key_preset_versions() {
            let old: Vec<_> = version
                .into_iter()
                .chain(preset::tap_preset_bindings(preset::TapPreset::RightHand))
                .map(|row| serde_json::to_value(row).unwrap())
                .collect();
            assert!(upgrade_legacy_defaults(&old).is_some());
            let mut customized = old;
            customized.remove(0);
            assert!(upgrade_legacy_defaults(&customized).is_none());
        }
    }
}
