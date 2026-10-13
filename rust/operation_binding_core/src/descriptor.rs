use crate::model::*;

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
        InputDescriptor::Mouse {
            area,
            button,
            action,
        } => {
            format!(
                "mouse:{button}:{}{}",
                pointer_action_str(*action),
                area_suffix(area.as_deref())
            )
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
        InputDescriptor::Touch {
            area,
            gesture,
            fingers,
        } => {
            format!(
                "touch:{fingers}:{}{}",
                touch_gesture_str(*gesture),
                area_suffix(area.as_deref())
            )
        }
        InputDescriptor::Gamepad { button } => format!("gamepad:{button}"),
        InputDescriptor::Radial { menu_id, item_id } => format!("radial:{menu_id}:{item_id}"),
        InputDescriptor::Command { command } => format!("command:{command}"),
    }
}

pub fn area(input: &InputDescriptor) -> Option<&str> {
    match input {
        InputDescriptor::Mouse { area, .. } | InputDescriptor::Touch { area, .. } => {
            area.as_deref()
        }
        _ => None,
    }
}

pub fn matches(binding: &InputDescriptor, event: &InputDescriptor) -> bool {
    let mut event = event.clone();
    if area(binding).is_none() {
        match &mut event {
            InputDescriptor::Mouse { area, .. } | InputDescriptor::Touch { area, .. } => {
                *area = None
            }
            _ => {}
        }
    }
    *binding == event
}

fn area_suffix(area: Option<&str>) -> String {
    area.map(|area| format!(":area:{area}")).unwrap_or_default()
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

fn wheel_direction_str(direction: crate::model::WheelDirection) -> &'static str {
    match direction {
        crate::model::WheelDirection::Up => "up",
        crate::model::WheelDirection::Down => "down",
    }
}

fn touch_gesture_str(gesture: crate::model::TouchGesture) -> &'static str {
    use crate::model::TouchGesture;
    match gesture {
        TouchGesture::SwipeLeft => "swipe-left",
        TouchGesture::SwipeRight => "swipe-right",
        TouchGesture::SwipeUp => "swipe-up",
        TouchGesture::SwipeDown => "swipe-down",
        TouchGesture::Tap => "tap",
        TouchGesture::DoubleTap => "double-tap",
        TouchGesture::LongPress => "long-press",
    }
}

fn gesture_direction_str(direction: crate::model::GestureDirection) -> &'static str {
    use crate::model::GestureDirection;
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
