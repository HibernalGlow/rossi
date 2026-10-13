//! Typed input protocol. Area and context identifiers belong to the host.

use serde::{Deserialize, Serialize};

use crate::context::ContextDefinition;
pub const MAX_ACTION_SEQUENCE_LENGTH: usize = 8;
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
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum TouchGesture {
    SwipeLeft,
    SwipeRight,
    SwipeUp,
    SwipeDown,
    Tap,
    DoubleTap,
    LongPress,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum GestureDirection {
    Left,
    Right,
    Up,
    Down,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "device",
    rename_all = "kebab-case",
    rename_all_fields = "camelCase"
)]
pub enum InputDescriptor {
    Keyboard {
        /// 平台无关键名（`ArrowLeft` / `KeyA` / `Numpad4` …）。
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
        #[serde(default, skip_serializing_if = "Option::is_none")]
        area: Option<String>,
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
        #[serde(default, skip_serializing_if = "Option::is_none")]
        area: Option<String>,
        gesture: TouchGesture,
        fingers: u8,
    },
    Gamepad {
        button: u16,
    },
    Radial {
        menu_id: String,
        item_id: String,
    },
    Command {
        command: String,
    },
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum GestureTrigger {
    Instant,
    Hold,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InputBinding {
    pub id: String,
    /// 主动作 id。
    pub action: String,
    /// 追加动作（按序执行）。空数组与缺字段等价。
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub follow_up_actions: Vec<String>,
    pub context: String,
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
pub fn bindings_are_valid(bindings: &[InputBinding]) -> bool {
    let mut ids = std::collections::HashSet::new();
    bindings.iter().all(|binding| {
        !binding.id.trim().is_empty()
            && ids.insert(&binding.id)
            && !binding.context.trim().is_empty()
            && !binding.action.trim().is_empty()
            && binding.follow_up_actions.len() < MAX_ACTION_SEQUENCE_LENGTH
            && binding
                .follow_up_actions
                .iter()
                .all(|action| !action.trim().is_empty())
            && input_area_valid(&binding.input)
            && match &binding.input {
                InputDescriptor::Keyboard { code, .. } => !code.trim().is_empty(),
                InputDescriptor::Mouse { button, .. } => *button < 8,
                InputDescriptor::MouseGesture {
                    button, directions, ..
                } => *button < 8 && !directions.is_empty() && directions.len() <= 16,
                InputDescriptor::Touch {
                    fingers, gesture, ..
                } => {
                    (1..=3).contains(fingers)
                        && (*gesture != TouchGesture::DoubleTap || *fingers == 1)
                }
                InputDescriptor::Gamepad { button } => *button < 32,
                InputDescriptor::Radial { menu_id, item_id } => {
                    !menu_id.is_empty() && !item_id.is_empty()
                }
                InputDescriptor::Command { command } => !command.trim().is_empty(),
                InputDescriptor::Wheel { .. } => true,
            }
    })
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InputBindingsConfig {
    pub format: String,
    pub format_version: u32,
    #[serde(default)]
    pub contexts: Vec<ContextDefinition>,
    pub bindings: Vec<InputBinding>,
}

impl InputBindingsConfig {
    pub fn new(bindings: Vec<InputBinding>) -> Self {
        Self {
            format: crate::migration::FORMAT.into(),
            format_version: crate::migration::CURRENT_VERSION,
            contexts: Vec::new(),
            bindings,
        }
    }
}

fn input_area_valid(input: &InputDescriptor) -> bool {
    match input {
        InputDescriptor::Mouse { area, .. } | InputDescriptor::Touch { area, .. } => {
            area.as_ref().is_none_or(|area| !area.trim().is_empty())
        }
        _ => true,
    }
}

impl InputBindingsConfig {
    /// A portable document must declare the contexts of all bindings.
    pub fn validate(&self) -> anyhow::Result<()> {
        anyhow::ensure!(
            self.format == crate::migration::FORMAT
                && self.format_version == crate::migration::CURRENT_VERSION,
            "Unsupported bindings format/version"
        );
        anyhow::ensure!(
            bindings_are_valid(&self.bindings),
            "Invalid binding parameters or duplicate ids"
        );
        crate::context::validate(&self.contexts)?;
        anyhow::ensure!(
            self.bindings
                .iter()
                .all(|row| self.contexts.iter().any(|def| def.id == row.context)),
            "Unknown binding context"
        );
        Ok(())
    }
}
