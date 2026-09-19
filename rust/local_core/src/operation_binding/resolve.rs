//! 解析器：冲突检测 + 「输入事件 → 该触发哪条绑定」——**本模块全部是纯函数**。
//!
//! 算法逐行对齐 neoview `packages/nodes/neoview/src/domain/input/ReaderInputBindings.ts`
//! 的 `readerInputConflictKey` / `readerInputConflicts` / `matchingReaderInputBinding`，
//! 以及 `features/input/ReaderInputActionExecutor.ts` 里那两行**空间动作**的解释。
//!
//! 「换外壳也能用」的接缝就在这里（ADR-0015 §5）：UI 只做三件事 ——
//! ① 把真实事件归一化成 [`InputDescriptor`]；② 报告当前活跃的 context 集合；
//! ③ 把解析出的 action id 映射到自己的执行体。**解析框架无关，执行必然框架绑定。**

use super::model::{GestureTrigger, InputBinding, InputDescriptor, KeyTrigger, PointerAction};
use super::vocabulary::{InputContext, ReaderViewArea, ReadingDirection, action};

/// 冲突：同一个 `context + 输入` 上挂了多条**启用**的绑定。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InputConflict {
    pub key: String,
    pub binding_ids: Vec<String>,
}

/// 冲突键 = `context:输入键`（neoview `readerInputConflictKey`）。
pub fn conflict_key(context: InputContext, input: &InputDescriptor) -> String {
    format!("{}:{}", context.as_str(), descriptor_key(input))
}

/// 输入键：**同样的输入必须产生同样的字符串**，否则冲突检测与绑定包 diff 都会失真。
///
/// 逐条对齐 neoview `readerInputDescriptorKey`，含修饰键的 `C-A-S-M` 四段格式与
/// `trigger` 的缺省值（`down`）。
pub fn descriptor_key(input: &InputDescriptor) -> String {
    match input {
        InputDescriptor::Keyboard {
            code,
            trigger,
            ctrl,
            alt,
            shift,
            meta,
        } => format!(
            "keyboard:{}:{code}:{}",
            modifiers(*ctrl, *alt, *shift, *meta),
            key_trigger_str(*trigger)
        ),
        InputDescriptor::Mouse { button, action } => {
            format!("mouse:{button}:{}", pointer_action_str(*action))
        }
        InputDescriptor::MouseGesture {
            button,
            directions,
            trigger,
        } => {
            let joined = directions
                .iter()
                .map(|direction| gesture_direction_str(*direction))
                .collect::<Vec<_>>()
                .join("-");
            format!(
                "mouse-gesture:{button}:{}:{joined}",
                gesture_trigger_str(*trigger)
            )
        }
        InputDescriptor::Wheel {
            direction,
            ctrl,
            alt,
            shift,
            meta,
        } => format!(
            "wheel:{}:{}",
            modifiers(*ctrl, *alt, *shift, *meta),
            wheel_direction_str(*direction)
        ),
        InputDescriptor::Touch { gesture, fingers } => {
            format!("touch:{fingers}:{}", touch_gesture_str(*gesture))
        }
        InputDescriptor::Gamepad { button } => format!("gamepad:{button}"),
        InputDescriptor::Area {
            area,
            button,
            action,
        } => format!("area:{area}:{button}:{}", pointer_action_str(*action)),
        InputDescriptor::Radial { menu_id, item_id } => format!("radial:{menu_id}:{item_id}"),
        InputDescriptor::Command { command } => format!("command:{command}"),
    }
}

/// 两条输入是否**等价**（同 device 且逐字段相等；`trigger` 缺省按 `down` 处理）。
///
/// 注意：**不比较 `durationMs` / `moveTolerancePx`** —— 与 neoview 一致。那两个是
/// 识别器的容忍参数，不进冲突键，也不该让「同一次点击」因容忍度不同而算成两条输入。
pub fn descriptors_equal(left: &InputDescriptor, right: &InputDescriptor) -> bool {
    match (left, right) {
        (
            InputDescriptor::Keyboard {
                code: left_code,
                trigger: left_trigger,
                ctrl: left_ctrl,
                alt: left_alt,
                shift: left_shift,
                meta: left_meta,
            },
            InputDescriptor::Keyboard {
                code: right_code,
                trigger: right_trigger,
                ctrl: right_ctrl,
                alt: right_alt,
                shift: right_shift,
                meta: right_meta,
            },
        ) => {
            left_code == right_code
                && left_trigger == right_trigger
                && same_modifiers(
                    (*left_ctrl, *left_alt, *left_shift, *left_meta),
                    (*right_ctrl, *right_alt, *right_shift, *right_meta),
                )
        }
        (
            InputDescriptor::Mouse {
                button: left_button,
                action: left_action,
            },
            InputDescriptor::Mouse {
                button: right_button,
                action: right_action,
            },
        ) => left_button == right_button && left_action == right_action,
        (
            InputDescriptor::MouseGesture {
                button: left_button,
                directions: left_directions,
                trigger: left_trigger,
            },
            InputDescriptor::MouseGesture {
                button: right_button,
                directions: right_directions,
                trigger: right_trigger,
            },
        ) => {
            left_button == right_button
                && left_trigger == right_trigger
                && left_directions == right_directions
        }
        (
            InputDescriptor::Wheel {
                direction: left_direction,
                ctrl: left_ctrl,
                alt: left_alt,
                shift: left_shift,
                meta: left_meta,
            },
            InputDescriptor::Wheel {
                direction: right_direction,
                ctrl: right_ctrl,
                alt: right_alt,
                shift: right_shift,
                meta: right_meta,
            },
        ) => {
            left_direction == right_direction
                && same_modifiers(
                    (*left_ctrl, *left_alt, *left_shift, *left_meta),
                    (*right_ctrl, *right_alt, *right_shift, *right_meta),
                )
        }
        (
            InputDescriptor::Touch {
                gesture: left_gesture,
                fingers: left_fingers,
            },
            InputDescriptor::Touch {
                gesture: right_gesture,
                fingers: right_fingers,
            },
        ) => left_gesture == right_gesture && left_fingers == right_fingers,
        (
            InputDescriptor::Gamepad {
                button: left_button,
            },
            InputDescriptor::Gamepad {
                button: right_button,
            },
        ) => left_button == right_button,
        (
            InputDescriptor::Area {
                area: left_area,
                button: left_button,
                action: left_action,
            },
            InputDescriptor::Area {
                area: right_area,
                button: right_button,
                action: right_action,
            },
        ) => left_area == right_area && left_button == right_button && left_action == right_action,
        (
            InputDescriptor::Radial {
                menu_id: left_menu,
                item_id: left_item,
            },
            InputDescriptor::Radial {
                menu_id: right_menu,
                item_id: right_item,
            },
        ) => left_menu == right_menu && left_item == right_item,
        (
            InputDescriptor::Command {
                command: left_command,
            },
            InputDescriptor::Command {
                command: right_command,
            },
        ) => left_command == right_command,
        _ => false,
    }
}

/// 找出所有冲突（同 `context + 输入` 上多于一条启用绑定）。
///
/// **冲突阻止保存**（neoview 同语义）：一个输入只能有一条生效绑定，多条并存意味着
/// 解析结果取决于注册顺序 —— 那是用户没法自查的错。所以这里把冲突**全列出来**，
/// 由设置页挡在保存之前，而不是安静地取第一条。
pub fn conflicts(bindings: &[InputBinding]) -> Vec<InputConflict> {
    let mut groups: Vec<(String, Vec<String>)> = Vec::new();
    for binding in bindings {
        if !binding.enabled {
            continue;
        }
        let key = conflict_key(binding.context, &binding.input);
        match groups.iter_mut().find(|(existing, _)| *existing == key) {
            Some((_, ids)) => ids.push(binding.id.clone()),
            None => groups.push((key, vec![binding.id.clone()])),
        }
    }
    groups
        .into_iter()
        .filter(|(_, ids)| ids.len() > 1)
        .map(|(key, binding_ids)| InputConflict { key, binding_ids })
        .collect()
}

/// 解析一次输入事件：返回**该触发哪条绑定**。
///
/// 规则（逐条照抄 neoview）：
/// 1. 跳过错用（`enabled == false`）；
/// 2. `context == global` 的绑定在**存在隔离 context**（`shell` / `editor` / `modal`）时
///    一律跳过 —— 隔离不是「优先级更低」，是「不生效」；
/// 3. 其余 context 必须在**活跃集合**里；
/// 4. 输入必须与绑定等价；
/// 5. 优先级**严格更大**才顶替 ⇒ 同优先级时**先注册者胜**。
///
/// 返回 `None` = 「没人认这个输入」，调用方照常往下冒泡（例如让方向键去做焦点遍历）。
pub fn resolve<'a>(
    bindings: &'a [InputBinding],
    input: &InputDescriptor,
    contexts: &[InputContext],
) -> Option<&'a InputBinding> {
    let isolates_global = contexts.iter().any(|context| context.isolates_global());
    let mut matched: Option<&InputBinding> = None;
    let mut matched_priority = i32::MIN;

    for candidate in bindings {
        if !candidate.enabled {
            continue;
        }
        if candidate.context == InputContext::Global {
            if isolates_global {
                continue;
            }
        } else if !contexts.contains(&candidate.context) {
            continue;
        }
        if !descriptors_equal(&candidate.input, input) {
            continue;
        }

        let priority = candidate.context.priority();
        if priority > matched_priority {
            matched = Some(candidate);
            matched_priority = priority;
        }
    }

    matched
}

/// 一次点击落在九宫格的哪一格（neoview `readerViewAreaAtPoint`）。
///
/// 分区是「宽/高各切三等份」，**越界一律夹回最外档**（`x < 0` ⇒ 最左列），与 neoview 的
/// `Math.max(0, Math.min(2, …))` 同语义。
///
/// 返回 `None` 的条件是**量不出格子**：宽或高非有限、或 ≤ 0。这一档不能瞎猜 ——
/// 宽为 0 时「三分法」会把**每一次点击**都判成同一格（neoview 在这个输入上会算出
/// `NaN` 索引）。调用方拿到 `None` 应当选**可逆**的那一档（唤出上下栏），
/// 而不是选翻页：翻页改阅读进度，还顺手把上下栏收起来。
pub fn reader_view_area_at_point(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
) -> Option<ReaderViewArea> {
    if !x.is_finite() || !y.is_finite() || !width.is_finite() || !height.is_finite() {
        return None;
    }
    if width <= 0.0 || height <= 0.0 {
        return None;
    }

    let column = ((x / width) * 3.0).floor().clamp(0.0, 2.0) as u8;
    let row = ((y / height) * 3.0).floor().clamp(0.0, 2.0) as u8;
    let index = row as usize * 3 + column as usize;
    ReaderViewArea::ALL.get(index).copied()
}

/// 翻页的**语义**结果。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PageTurn {
    Next,
    Previous,
}

/// 把一条翻页动作解释成「下一页 / 上一页」——**这就是阅读方向唯一生效的地方**。
///
/// 四条动作分成两族（neoview `ReaderInputActionExecutor` 的 99–104 行）：
///
/// - **语义族**：`reader.next-page` / `reader.previous-page` —— 不论在哪个方向下，
///   「下一页」就是下一页。适合绑到「前进/后退」这种与画面无关的意图上
///   （竖向滚动、幻灯片、遥控器）。
/// - **空间族**：`reader.page-left` / `reader.page-right` —— 说的是**画面往哪边翻**。
///   右开（left-to-right）时向右是前进；左开（right-to-left，漫画）时**向右是退回**。
///
/// 为什么空间族非有不可：只把「左半=上一页、右半=下一页」写死的话，左开模式下
/// 用户点屏幕右边（靠拇指的一侧）会得到「下一页」，而下一页其实在左边 ——
/// 手里那本书翻不动/翻反了。老实现正是如此（`reader_gesture_logic.dart` 的分区
/// 完全不认识方向），所以九宫格必须绑**空间动作**，方向在派发时解释。
pub fn resolve_page_turn(action_id: &str, direction: ReadingDirection) -> Option<PageTurn> {
    match action_id {
        action::NEXT_PAGE => Some(PageTurn::Next),
        action::PREVIOUS_PAGE => Some(PageTurn::Previous),
        action::PAGE_LEFT => Some(match direction {
            ReadingDirection::RightToLeft => PageTurn::Next,
            ReadingDirection::LeftToRight => PageTurn::Previous,
        }),
        action::PAGE_RIGHT => Some(match direction {
            ReadingDirection::RightToLeft => PageTurn::Previous,
            ReadingDirection::LeftToRight => PageTurn::Next,
        }),
        _ => None,
    }
}

fn same_modifiers(left: (bool, bool, bool, bool), right: (bool, bool, bool, bool)) -> bool {
    left == right
}

fn modifiers(ctrl: bool, alt: bool, shift: bool, meta: bool) -> String {
    format!(
        "{}{}{}{}",
        if ctrl { "C" } else { "-" },
        if alt { "A" } else { "-" },
        if shift { "S" } else { "-" },
        if meta { "M" } else { "-" },
    )
}

fn key_trigger_str(trigger: KeyTrigger) -> &'static str {
    match trigger {
        KeyTrigger::Down => "down",
        KeyTrigger::Hold => "hold",
    }
}

fn pointer_action_str(action: PointerAction) -> &'static str {
    match action {
        PointerAction::Click => "click",
        PointerAction::DoubleClick => "double-click",
        PointerAction::Press => "press",
        PointerAction::Hold => "hold",
    }
}

fn wheel_direction_str(direction: super::model::WheelDirection) -> &'static str {
    match direction {
        super::model::WheelDirection::Up => "up",
        super::model::WheelDirection::Down => "down",
    }
}

fn touch_gesture_str(gesture: super::model::TouchGesture) -> &'static str {
    use super::model::TouchGesture;
    match gesture {
        TouchGesture::SwipeLeft => "swipe-left",
        TouchGesture::SwipeRight => "swipe-right",
        TouchGesture::SwipeUp => "swipe-up",
        TouchGesture::SwipeDown => "swipe-down",
        TouchGesture::Tap => "tap",
        TouchGesture::LongPress => "long-press",
    }
}

fn gesture_direction_str(direction: super::model::GestureDirection) -> &'static str {
    use super::model::GestureDirection;
    match direction {
        GestureDirection::Left => "left",
        GestureDirection::Right => "right",
        GestureDirection::Up => "up",
        GestureDirection::Down => "down",
    }
}

fn gesture_trigger_str(trigger: GestureTrigger) -> &'static str {
    match trigger {
        GestureTrigger::Instant => "instant",
        GestureTrigger::Hold => "hold",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::operation_binding::preset::TapPreset;
    use crate::operation_binding::preset::tap_preset_bindings;
    use crate::operation_binding::vocabulary::InputContext as Context;
    use crate::operation_binding::vocabulary::action as act;

    fn area_binding(
        id: &str,
        area: ReaderViewArea,
        action_id: &str,
        context: Context,
    ) -> InputBinding {
        InputBinding {
            id: id.into(),
            action: action_id.into(),
            follow_up_actions: Vec::new(),
            context,
            enabled: true,
            ignore_repeat: false,
            input: InputDescriptor::Area {
                area,
                button: 0,
                action: PointerAction::Click,
            },
        }
    }

    fn key_binding(id: &str, code: &str, action_id: &str, context: Context) -> InputBinding {
        InputBinding {
            id: id.into(),
            action: action_id.into(),
            follow_up_actions: Vec::new(),
            context,
            enabled: true,
            ignore_repeat: false,
            input: InputDescriptor::Keyboard {
                code: code.into(),
                trigger: KeyTrigger::Down,
                ctrl: false,
                alt: false,
                shift: false,
                meta: false,
            },
        }
    }

    fn area_click(area: ReaderViewArea) -> InputDescriptor {
        InputDescriptor::Area {
            area,
            button: 0,
            action: PointerAction::Click,
        }
    }

    // ── 判据 E1：解析是纯函数，输入一样则结论一样 ──────────────────────────

    #[test]
    fn resolve_picks_the_highest_priority_context() {
        // 同一个输入在 global 与 reader 各有一条；reader(100) > global(0)。
        let bindings = vec![
            key_binding("g", "ArrowRight", act::NEXT_PAGE, Context::Global),
            key_binding("r", "ArrowRight", act::PAGE_RIGHT, Context::Reader),
        ];
        let matched = resolve(
            &bindings,
            &key_binding("probe", "ArrowRight", "", Context::Reader).input,
            &[Context::Reader],
        )
        .expect("应命中 reader 那条");
        assert_eq!(matched.action, act::PAGE_RIGHT);
        assert_eq!(matched.id, "r");
    }

    #[test]
    fn resolve_isolates_global_when_a_shell_context_is_present() {
        let bindings = vec![
            key_binding("g", "ArrowRight", act::NEXT_PAGE, Context::Global),
            key_binding("r", "ArrowRight", act::PAGE_RIGHT, Context::Reader),
        ];
        let input = key_binding("probe", "ArrowRight", "", Context::Reader).input;

        // shell 在场（例如侧栏展开）：global 的绑定不生效，reader 的仍然生效。
        let matched = resolve(&bindings, &input, &[Context::Reader, Context::Shell]).unwrap();
        assert_eq!(matched.id, "r");

        // 只有 shell 在场时：reader 不在活跃集合，global 又被隔离 ⇒ 无人认领。
        assert_eq!(resolve(&bindings, &input, &[Context::Shell]), None);
    }

    #[test]
    fn resolve_ignores_disabled_bindings_and_unknown_inputs() {
        let mut disabled = key_binding("g", "ArrowRight", act::NEXT_PAGE, Context::Global);
        disabled.enabled = false;
        assert_eq!(
            resolve(
                &[disabled],
                &area_click(ReaderViewArea::TopLeft),
                &[Context::Reader]
            ),
            None
        );

        let bindings = vec![key_binding(
            "g",
            "ArrowRight",
            act::NEXT_PAGE,
            Context::Global,
        )];
        let other = key_binding("probe", "ArrowLeft", "", Context::Reader).input;
        assert_eq!(resolve(&bindings, &other, &[Context::Reader]), None);
    }

    #[test]
    fn same_priority_keeps_the_first_registered() {
        // 两条都是 reader（同优先级）：**先注册者胜**，与 neoview 的 `>` 语义一致。
        let bindings = vec![
            key_binding("first", "ArrowRight", act::NEXT_PAGE, Context::Reader),
            key_binding("second", "ArrowRight", act::PAGE_RIGHT, Context::Reader),
        ];
        let input = key_binding("probe", "ArrowRight", "", Context::Reader).input;
        assert_eq!(
            resolve(&bindings, &input, &[Context::Reader]).unwrap().id,
            "first"
        );
    }

    // ── 冲突检测 ────────────────────────────────────────────────────────────

    #[test]
    fn conflicts_only_report_enabled_duplicates() {
        let bindings = vec![
            area_binding(
                "a",
                ReaderViewArea::MiddleRight,
                act::PAGE_RIGHT,
                Context::Reader,
            ),
            area_binding(
                "b",
                ReaderViewArea::MiddleRight,
                act::NEXT_PAGE,
                Context::Reader,
            ),
            area_binding(
                "c",
                ReaderViewArea::MiddleLeft,
                act::PAGE_LEFT,
                Context::Reader,
            ),
        ];
        let found = conflicts(&bindings);
        assert_eq!(found.len(), 1, "只有右中格重复：{found:?}");
        assert_eq!(found[0].key, "reader:area:middle-right:0:click");
        assert_eq!(found[0].binding_ids, vec!["a", "b"]);

        // 关掉一条，冲突消失（禁用绑定不参与冲突）。
        let mut fixed = bindings.clone();
        fixed[1].enabled = false;
        assert!(conflicts(&fixed).is_empty());
    }

    #[test]
    fn conflict_key_distinguishes_context_and_modifiers() {
        let plain = key_binding("x", "ArrowRight", act::NEXT_PAGE, Context::Reader).input;
        let mut ctrl = plain.clone();
        if let InputDescriptor::Keyboard { ctrl: flag, .. } = &mut ctrl {
            *flag = true;
        }
        assert_ne!(descriptor_key(&plain), descriptor_key(&ctrl));
        assert_eq!(
            descriptor_key(&plain),
            "keyboard:----:ArrowRight:down",
            "修饰键四段格式与 trigger 缺省值与 neoview 一致"
        );
        assert_ne!(
            conflict_key(Context::Reader, &plain),
            conflict_key(Context::Global, &plain),
            "同输入不同 context 不算冲突"
        );
    }

    #[test]
    fn descriptor_key_covers_every_device() {
        // 每一类都要有稳定的键（否则冲突检测对那一类静默失效）。
        let samples = vec![
            InputDescriptor::Mouse {
                button: 3,
                action: PointerAction::Click,
            },
            InputDescriptor::MouseGesture {
                button: 2,
                directions: vec![
                    crate::operation_binding::model::GestureDirection::Left,
                    crate::operation_binding::model::GestureDirection::Up,
                ],
                trigger: GestureTrigger::Instant,
            },
            InputDescriptor::Wheel {
                direction: crate::operation_binding::model::WheelDirection::Down,
                ctrl: false,
                alt: false,
                shift: false,
                meta: false,
            },
            InputDescriptor::Touch {
                gesture: crate::operation_binding::model::TouchGesture::SwipeLeft,
                fingers: 1,
            },
            InputDescriptor::Gamepad { button: 3 },
            area_click(ReaderViewArea::MiddleLeft),
            InputDescriptor::Radial {
                menu_id: "default".into(),
                item_id: "radial-next-page".into(),
            },
            InputDescriptor::Command {
                command: "file-card.trash-current".into(),
            },
        ];
        let keys: Vec<String> = samples.iter().map(descriptor_key).collect();
        let unique: std::collections::HashSet<&String> = keys.iter().collect();
        assert_eq!(keys.len(), unique.len(), "键不许撞：{keys:?}");
        assert!(keys.iter().all(|key| !key.is_empty()));

        // 自己和自己必须等价（否则同一输入永远匹配不上）。
        for sample in &samples {
            assert!(descriptors_equal(sample, sample), "{sample:?}");
        }
    }

    // ── 九宫格归一化 ────────────────────────────────────────────────────────

    #[test]
    fn nine_grid_splits_into_thirds_including_edges() {
        let (w, h) = (900.0, 600.0);
        let cases = [
            (1.0, 1.0, ReaderViewArea::TopLeft),
            (450.0, 1.0, ReaderViewArea::TopCenter),
            (899.0, 1.0, ReaderViewArea::TopRight),
            (1.0, 300.0, ReaderViewArea::MiddleLeft),
            (450.0, 300.0, ReaderViewArea::MiddleCenter),
            (899.0, 300.0, ReaderViewArea::MiddleRight),
            (1.0, 599.0, ReaderViewArea::BottomLeft),
            (450.0, 599.0, ReaderViewArea::BottomCenter),
            (899.0, 599.0, ReaderViewArea::BottomRight),
            // 边界：正好落在 1/3 处属于**下一格**（`floor`），与 neoview 一致。
            (300.0, 300.0, ReaderViewArea::MiddleCenter),
            (299.9, 300.0, ReaderViewArea::MiddleLeft),
            // 越界夹回最外档。
            (-50.0, -50.0, ReaderViewArea::TopLeft),
            (5000.0, 5000.0, ReaderViewArea::BottomRight),
        ];
        for (x, y, expected) in cases {
            assert_eq!(
                reader_view_area_at_point(x, y, w, h),
                Some(expected),
                "({x},{y}) 落在 {expected}"
            );
        }
    }

    #[test]
    fn degenerate_viewport_has_no_cell() {
        // 量不出格子时返回 None（调用方选「唤出上下栏」这一可逆档，而不是翻页）。
        assert_eq!(reader_view_area_at_point(10.0, 10.0, 0.0, 600.0), None);
        assert_eq!(reader_view_area_at_point(10.0, 10.0, 900.0, 0.0), None);
        assert_eq!(
            reader_view_area_at_point(10.0, 10.0, f64::INFINITY, 600.0),
            None
        );
        assert_eq!(
            reader_view_area_at_point(f64::NAN, 10.0, 900.0, 600.0),
            None
        );
        assert_eq!(reader_view_area_at_point(10.0, 10.0, -5.0, 600.0), None);
    }

    // ── 空间动作 × 阅读方向（本次要修的 bug） ──────────────────────────────

    #[test]
    fn spatial_page_turn_follows_reading_direction() {
        use PageTurn::{Next, Previous};
        use ReadingDirection::{LeftToRight, RightToLeft};

        // 语义族：与方向无关。
        for direction in [LeftToRight, RightToLeft] {
            assert_eq!(resolve_page_turn(act::NEXT_PAGE, direction), Some(Next));
            assert_eq!(
                resolve_page_turn(act::PREVIOUS_PAGE, direction),
                Some(Previous)
            );
        }

        // 空间族：右开时「向右 = 下一页」，左开时「向右 = 上一页」。
        assert_eq!(resolve_page_turn(act::PAGE_RIGHT, LeftToRight), Some(Next));
        assert_eq!(
            resolve_page_turn(act::PAGE_RIGHT, RightToLeft),
            Some(Previous),
            "左开（漫画）下点右边是**退回** —— 下一页在左边"
        );
        assert_eq!(
            resolve_page_turn(act::PAGE_LEFT, LeftToRight),
            Some(Previous)
        );
        assert_eq!(
            resolve_page_turn(act::PAGE_LEFT, RightToLeft),
            Some(Next),
            "左开下点左边才是前进"
        );

        // 与翻页无关的动作不是翻页。
        assert_eq!(resolve_page_turn(act::FULLSCREEN, LeftToRight), None);
        assert_eq!(resolve_page_turn(act::TOGGLE_CONTROLS, RightToLeft), None);
    }

    #[test]
    fn right_to_left_semantics_hold_through_the_whole_pipeline() {
        // 端到端（纯函数版）：左开 + 点右中格 ⇒ 绑定是 page-right ⇒ 解出来是「上一页」。
        let bindings = tap_preset_bindings(TapPreset::RightHand);
        let resolved = resolve(
            &bindings,
            &area_click(ReaderViewArea::MiddleRight),
            &[Context::Reader],
        )
        .expect("右中格必须绑到了东西");
        assert_eq!(resolved.action, act::PAGE_RIGHT);
        assert_eq!(
            resolve_page_turn(&resolved.action, ReadingDirection::RightToLeft),
            Some(PageTurn::Previous),
        );

        // 右开同样的点 ⇒ 下一页。
        assert_eq!(
            resolve_page_turn(&resolved.action, ReadingDirection::LeftToRight),
            Some(PageTurn::Next),
        );
    }
}
