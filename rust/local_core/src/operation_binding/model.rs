//! 绑定与输入描述符的**数据模型**（neoview 的 schema，mImageViewer 的策略见 `preset.rs`）。
//!
//! 九类 descriptor 全部在这里（`keyboard` / `mouse` / `mouse-gesture` / `wheel` / `touch` /
//! `gamepad` / `area` / `radial` / `command`），因为它们**是要落进绑定包的东西**：
//! v0.1 运行时只产生前五类事件（ADR-0015 §2），但**导入一份 neoview 的绑定包时，
//! 后四类必须能被解析并原样存回去**，否则一次导出/导入就把用户的手柄绑定洗掉了。
//! 「只可解析、不可编辑」说的正是这件事，不是「模型里没有」。

use serde::{Deserialize, Serialize};

use super::vocabulary::{InputContext, ReaderViewArea};

/// 一个动作后面的**追加动作序列**上限（neoview `MAX_READER_INPUT_ACTION_SEQUENCE_LENGTH`）。
pub const MAX_ACTION_SEQUENCE_LENGTH: usize = 8;

/// 键盘触发时机（neoview `trigger`）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum KeyTrigger {
    Down,
    Hold,
}

impl Default for KeyTrigger {
    fn default() -> Self {
        Self::Down
    }
}

/// 指针动作（neoview `mouse.button` 那组 `action`）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum PointerAction {
    Click,
    DoubleClick,
    Press,
    Hold,
}

/// 滚轮方向。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum WheelDirection {
    Up,
    Down,
}

/// 触摸手势（neoview `touch.gesture`）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum TouchGesture {
    SwipeLeft,
    SwipeRight,
    SwipeUp,
    SwipeDown,
    Tap,
    LongPress,
}

/// 轨迹手势的方向（neoview `mouse-gesture.directions` 的元素）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum GestureDirection {
    Left,
    Right,
    Up,
    Down,
}

/// 归一化输入事件 / 绑定目标（neoview `ReaderInputDescriptor` 的联合体）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "device",
    rename_all = "kebab-case",
    rename_all_fields = "camelCase"
)]
pub enum InputDescriptor {
    Keyboard {
        /// 平台无关键名（`ArrowLeft` / `KeyA` / `Numpad4` …）。
        /// `LogicalKeyboardKey ⇄ 这个字符串` 的映射归**外壳**（ADR-0015 §6）。
        code: String,
        #[serde(default)]
        trigger: KeyTrigger,
        #[serde(default)]
        ctrl: bool,
        #[serde(default)]
        alt: bool,
        #[serde(default)]
        shift: bool,
        #[serde(default)]
        meta: bool,
    },
    Mouse {
        button: u8,
        action: PointerAction,
    },
    MouseGesture {
        button: u8,
        directions: Vec<GestureDirection>,
        trigger: GestureTrigger,
    },
    Wheel {
        direction: WheelDirection,
        #[serde(default)]
        ctrl: bool,
        #[serde(default)]
        alt: bool,
        #[serde(default)]
        shift: bool,
        #[serde(default)]
        meta: bool,
    },
    Touch {
        gesture: TouchGesture,
        fingers: u8,
    },
    Gamepad {
        button: u16,
    },
    /// 画面九宫格（本仓 v0.1 用来承载「点击左右两半翻页」）。
    Area {
        area: ReaderViewArea,
        button: u8,
        action: PointerAction,
    },
    Radial {
        menu_id: String,
        item_id: String,
    },
    Command {
        command: String,
    },
}

/// 轨迹手势的触发时机（neoview `instant` / `hold`）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum GestureTrigger {
    Instant,
    Hold,
}

/// 一条绑定：**动作 + 追加动作 + context + 开关 + 输入**（neoview `ReaderInputBinding`）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InputBinding {
    pub id: String,
    /// 主动作 id。
    pub action: String,
    /// 追加动作（按序执行）。空数组与缺字段等价。
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub follow_up_actions: Vec<String>,
    pub context: InputContext,
    pub enabled: bool,
    /// 长按重复是否忽略（按住不放只触发一次）。
    #[serde(default)]
    pub ignore_repeat: bool,
    pub input: InputDescriptor,
}

impl InputBinding {
    /// 一条绑定会执行的动作序列（主动作在前）。
    pub fn actions(&self) -> Vec<&str> {
        let mut actions = Vec::with_capacity(1 + self.follow_up_actions.len());
        actions.push(self.action.as_str());
        actions.extend(self.follow_up_actions.iter().map(String::as_str));
        actions
    }
}

/// 编辑 / 导入时的完整性检查。主动作计入 Neo 的八步上限。
pub fn bindings_are_valid(bindings: &[InputBinding]) -> bool {
    let mut ids = std::collections::HashSet::new();
    bindings.iter().all(|binding| {
        !binding.id.trim().is_empty()
            && ids.insert(&binding.id)
            && !binding.action.trim().is_empty()
            && binding.follow_up_actions.len() < MAX_ACTION_SEQUENCE_LENGTH
            && binding
                .follow_up_actions
                .iter()
                .all(|action| !action.trim().is_empty())
            && match &binding.input {
                InputDescriptor::Keyboard { code, .. } => !code.trim().is_empty(),
                InputDescriptor::Mouse { button, .. } => *button < 8,
                InputDescriptor::MouseGesture {
                    button, directions, ..
                } => *button < 8 && !directions.is_empty() && directions.len() <= 16,
                InputDescriptor::Touch { fingers, .. } => (1..=3).contains(fingers),
                InputDescriptor::Gamepad { button } => *button < 32,
                InputDescriptor::Area { button, .. } => *button < 3,
                InputDescriptor::Radial { menu_id, item_id } => {
                    !menu_id.is_empty() && !item_id.is_empty()
                }
                InputDescriptor::Command { command } => !command.trim().is_empty(),
                InputDescriptor::Wheel { .. } => true,
            }
    })
}

/// 绑定包（导出 = 直接写这个结构的 JSON，见 ADR-0015 §7）。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InputBindingsConfig {
    pub bindings: Vec<InputBinding>,
}

impl InputBindingsConfig {
    pub fn new(bindings: Vec<InputBinding>) -> Self {
        Self { bindings }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
            r#"{"device":"area","area":"middle-left","button":0,"action":"click"}"#,
        )
        .unwrap();
        assert_eq!(
            area,
            InputDescriptor::Area {
                area: ReaderViewArea::MiddleLeft,
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
            context: InputContext::Reader,
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
             "input":{"device":"area","area":"middle-left","button":0,"action":"click"}},
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
