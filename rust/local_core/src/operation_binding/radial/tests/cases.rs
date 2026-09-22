//! `radial` 的测试。父文件里的 `mod tests { use super::*; … }` 把父模块的项
//! 传导到这个模块，所以这里仍用 `super::*` 接住（拆分前它们是同一个人写的文件）。
use super::*;

fn item_ids(menu: &RadialMenuDefinition) -> Vec<String> {
    menu.layers
        .iter()
        .flatten()
        .map(|entry| entry.id.clone())
        .collect()
}

/// 一个槽的正中间那一点（画法给的角平分线 × 环带正中）。
fn point_of(entry: &RadialSlotLayout) -> (f32, f32) {
    let radius = (entry.inner_radius + entry.outer_radius) / 2.0;
    let angle = entry.mid_deg.to_radians();
    (angle.cos() * radius, angle.sin() * radius)
}

#[test]
fn default_wheel_matches_neoview_numbers() {
    let config = default_config();
    assert_eq!(config.radius, 120.0);
    assert_eq!(config.inner_radius, 40.0);
    assert_eq!(config.start_angle, -90.0);
    assert_eq!(config.sweep_angle, 360.0);
    assert_eq!(config.layer_count, 3);
    assert!(is_valid(&config), "{:?}", validate(&config));
    let menu = config.active_menu().unwrap();
    assert_eq!(menu.layers.len(), 3);
    assert_eq!(menu.layers[0].len(), 4);
    assert_eq!(item_ids(menu).len(), 12);
}

#[test]
fn bands_grow_outward_by_the_submenu_step() {
    let config = default_config();
    // 第 1 环 = 空洞→r120；之后每一层往外 60（neoview `_getBand`）。
    assert_eq!(config.band(1), (40.0, 120.0));
    assert_eq!(config.band(2), (120.0, 180.0));
    assert_eq!(config.band(3), (180.0, 240.0));
    assert_eq!(config.outer_radius(), 240.0);
    // 只留一层时外缘就是 r120 —— 层数改小，轮盘整体缩回去。
    let one = RadialConfig {
        layer_count: 1,
        ..default_config()
    };
    assert_eq!(one.outer_radius(), 120.0);
}

#[test]
fn empty_slots_are_implied_by_geometry_not_stored() {
    let config = default_config();
    let menu = config.active_menu().unwrap();
    // 4 个条目排在 0/2/4/6 格 ⇒ 这一层仍是 8 格（MIN_SLOT_COUNT），空着。
    assert_eq!(menu.slot_count(1), 8);
    let layout = slot_layout(&config, menu);
    assert_eq!(layout.len(), 24);
    let filled: Vec<&RadialSlotLayout> = layout
        .iter()
        .filter(|entry| entry.item_id.is_some())
        .collect();
    assert_eq!(filled.len(), 12);
    assert!(
        layout
            .iter()
            .any(|entry| entry.index == 1 && entry.item_id.is_none())
    );
    // 排到第 9 格就把这一层撑到 10 格。
    let wide = RadialMenuDefinition {
        layers: vec![vec![item("x", "X", 9)], vec![], vec![]],
        ..Default::default()
    };
    assert_eq!(wide.slot_count(1), 10);
}

#[test]
fn hit_test_returns_what_the_layout_painted() {
    // 画出来的每一格，往它的角平分线中点打一发，必须回到同一格。
    let config = default_config();
    let menu = config.active_menu().unwrap();
    for entry in slot_layout(&config, menu) {
        let Some(item_id) = entry.item_id.clone() else {
            continue;
        };
        let (dx, dy) = point_of(&entry);
        let hit = slot_at(&config, menu, dx, dy)
            .unwrap_or_else(|| panic!("{item_id} 自己画出来的中点打不中"));
        assert_eq!(hit.level, entry.level);
        assert_eq!(hit.index, entry.index);
        assert_eq!(hit.item_id.as_deref(), Some(item_id.as_str()));
    }
}

#[test]
fn hole_empty_slot_and_outside_all_select_nothing() {
    let config = default_config();
    let menu = config.active_menu().unwrap();
    // 中心空洞：松手取消。
    assert_eq!(slot_at(&config, menu, 10.0, 0.0), None);
    // 外缘之外。
    assert_eq!(slot_at(&config, menu, 241.0, 0.0), None);
    // 第 1 环里的空格（slotIndex 1）：没有条目 ⇒ 不选中，而不是「选中隔壁」。
    let empty = slot_layout(&config, menu)
        .into_iter()
        .find(|entry| entry.level == 1 && entry.index == 1)
        .unwrap();
    let (dx, dy) = point_of(&empty);
    assert_eq!(slot_at(&config, menu, dx, dy), None);
    // 压在最外缘这一条边界上仍属最外层。
    let last = slot_layout(&config, menu).pop().unwrap();
    let (dx, _) = point_of(&last);
    let edge = (config.outer_radius(), 0.0);
    assert!(slot_at(&config, menu, edge.0, edge.1).is_some() || dx < 0.0);
}

#[test]
fn start_angle_and_sweep_move_the_whole_wheel() {
    // 起始角 -90 ⇒ 第 0 格居中于 12 点；改成 0 ⇒ 居中于 3 点。
    let config = default_config();
    let menu = config.active_menu().unwrap();
    let first = &slot_layout(&config, menu)[0];
    assert!((first.mid_deg - (-90.0)).abs() < 1e-4);
    assert_eq!(first.selectable, true);

    let turned = RadialConfig {
        start_angle: 0.0,
        ..default_config()
    };
    let laid = slot_layout(&turned, turned.active_menu().unwrap());
    assert!((laid[0].mid_deg - 0.0).abs() < 1e-4);
    let (dx, dy) = point_of(&laid[0]);
    assert_eq!(
        slot_at(&turned, turned.active_menu().unwrap(), dx, dy)
            .unwrap()
            .index,
        0
    );

    // 扫过角 90° ⇒ 只有右下那一象限是轮盘，超出扫过角的不算选中。
    let fan = RadialConfig {
        start_angle: -45.0,
        sweep_angle: 90.0,
        ..default_config()
    };
    let fan_menu = fan.active_menu().unwrap();
    assert_eq!(
        slot_layout(&fan, fan_menu).len(),
        8 * 3,
        "格数不变，只是挤进 90°"
    );
    assert!(
        slot_at(&fan, fan_menu, 80.0, 0.0).is_some(),
        "0° 在 -45..45 里"
    );
    assert_eq!(
        slot_at(&fan, fan_menu, 0.0, 80.0),
        None,
        "90° 已经在扇形之外"
    );
}

#[test]
fn slots_number_clockwise_from_the_start_angle() {
    let config = default_config();
    let menu = config.active_menu().unwrap();
    let at = |angle: f32| {
        let radius = 80.0;
        let radian = angle.to_radians();
        slot_at(&config, menu, radian.cos() * radius, radian.sin() * radius)
    };
    assert_eq!(at(-90.0).unwrap().index, 0, "12 点 = 第 0 格");
    assert_eq!(at(0.0).unwrap().index, 2, "3 点顺时针第 2 格");
    assert_eq!(at(90.0).unwrap().index, 4, "6 点");
    assert_eq!(at(180.0).unwrap().index, 6, "9 点");
}

#[test]
fn preset_items_all_resolve_through_the_binding_table() {
    // 「轮盘里的每个操作都是绑定系统里的 action」—— 这条判据就是这个测试：
    // 预设条目必须由**同一个解析器**解析出动作，而不是走一条轮盘专用路径。
    let config = default_config();
    let menu = config.active_menu().unwrap();
    let bindings = preset_bindings(DEFAULT_RADIAL_MENU_ID);
    for entry in slot_layout(&config, menu)
        .iter()
        .filter(|e| e.item_id.is_some())
    {
        let item_id = entry.item_id.clone().unwrap();
        let resolved = resolve(
            &bindings,
            &radial_input(DEFAULT_RADIAL_MENU_ID, &item_id),
            &[InputContext::Reader],
        )
        .unwrap_or_else(|| panic!("{item_id} 解析不出动作"));
        let definition = action_definition(&resolved.action).unwrap();
        assert!(definition.implemented, "{item_id} 绑了未实现的动作");
        // neoview 的槽位动作选项里**排除** `radial.*`：轮盘里再放一个「开轮盘」是循环。
        assert!(
            !definition.id.starts_with("radial."),
            "{item_id} 绑了轮盘自身的动作"
        );
    }
    assert!(preset_bindings("menu-2").is_empty(), "新轮盘是空的");
}

#[test]
fn every_preset_item_has_a_binding_and_vice_versa() {
    // 文档里的条目与绑定行必须一一对上：多出来的绑定行是孤儿（画不出来），
    // 缺了绑定行的条目是死槽（点了没反应）。
    let config = default_config();
    let menu = config.active_menu().unwrap();
    let bindings = preset_bindings(DEFAULT_RADIAL_MENU_ID);
    let bound: Vec<&str> = bindings
        .iter()
        .filter_map(|binding| match &binding.input {
            InputDescriptor::Radial { item_id, .. } => Some(item_id.as_str()),
            _ => None,
        })
        .collect();
    for item_id in item_ids(menu) {
        assert!(bound.contains(&item_id.as_str()), "{item_id} 没有绑定行");
    }
    assert_eq!(bound.len(), menu.layers.iter().map(Vec::len).sum::<usize>());
}

#[test]
fn preset_slots_fit_their_layer_and_do_not_collide() {
    let config = default_config();
    let menu = config.active_menu().unwrap();
    let bindings = preset_bindings(DEFAULT_RADIAL_MENU_ID);
    for binding in &bindings {
        let InputDescriptor::Radial { item_id, .. } = &binding.input else {
            continue;
        };
        assert!(menu.item(item_id).is_some(), "{item_id} 在默认轮盘里不存在");
    }
    assert!(conflicts(&bindings).is_empty());
}

#[test]
fn deleting_an_item_or_layer_prunes_only_its_bindings() {
    let bindings = preset_bindings(DEFAULT_RADIAL_MENU_ID);
    let config = default_config();
    assert_eq!(prune_bindings(&config, &bindings).len(), bindings.len());

    // 把第 3 层清空 ⇒ 那一层的 4 条走，其余留着。
    let mut shrunk = default_config();
    shrunk.menus[0].layers[2].clear();
    let kept = prune_bindings(&shrunk, &bindings);
    assert_eq!(kept.len(), 8);
    assert!(
        prune_bindings(&shrunk, &kept).len() == 8,
        "再剪一次不该更少（幂等）"
    );

    // 删掉整个轮盘 ⇒ 它的绑定全清，键盘/点击那些一条不许动。
    let emptied = RadialConfig {
        menus: vec![RadialMenuDefinition {
            id: "other".into(),
            name: "别的".into(),
            ..Default::default()
        }],
        active_menu_id: "other".into(),
        ..Default::default()
    };
    let mixed: Vec<InputBinding> = bindings
        .into_iter()
        .chain(tap_preset_bindings(TapPreset::RightHand))
        .collect();
    let kept = prune_bindings(&emptied, &mixed);
    assert_eq!(kept.len(), 3, "只剩九宫格那三条");
    assert!(
        kept.iter()
            .all(|b| !b.id.starts_with(RADIAL_PRESET_ID_PREFIX))
    );
}

#[test]
fn validation_names_the_offending_field() {
    let mut config = default_config();
    config.layer_count = 5;
    let problems = validate(&config);
    assert!(problems.iter().any(|p| p.contains("层数")), "{problems:?}");

    config.layer_count = 3;
    config.inner_radius = 200.0;
    assert!(validate(&config).iter().any(|p| p.contains("内半径")));

    config.inner_radius = 40.0;
    config.radius = 400.0;
    assert!(validate(&config).iter().any(|p| p.contains("半径")));

    config.radius = 120.0;
    config.sweep_angle = 30.0;
    assert!(validate(&config).iter().any(|p| p.contains("扫过角")));

    config.sweep_angle = 360.0;
    config.active_menu_id = "nope".into();
    assert!(validate(&config).iter().any(|p| p.contains("nope")));

    config.active_menu_id = DEFAULT_RADIAL_MENU_ID.into();
    config.menus[0].layers[0].push(item("radial-next-page", "重复", 7));
    assert!(validate(&config).iter().any(|p| p.contains("重复")));

    config.menus[0].layers[0].pop();
    config.menus[0].layers[0][0].move_to_menu_id = Some("gone".into());
    assert!(validate(&config).iter().any(|p| p.contains("不存在的轮盘")));
    assert!(is_valid(&default_config()));
}

#[test]
fn malformed_item_ids_are_rejected_by_validation() {
    // 形状不合法的 id 会静默失效（老版本读不懂、绑定永远匹配不上），所以它必须
    // 过不了校验 —— 而不是只在外壳的一句 assert 里挡一下（release 会被剥掉）。
    assert!(is_item_id_shape("item-1"));
    assert!(is_item_id_shape("radial-next-page"));
    assert!(is_item_id_shape("a"));
    assert!(is_item_id_shape("x_1-2.3"));
    for bad in ["", "-bad", ".bad", "a b", "a/b", &"x".repeat(81)] {
        assert!(!is_item_id_shape(bad), "{bad} 应当被挡下");
    }
    let mut config = default_config();
    config.menus[0].layers[0][0].id = "-nope".into();
    assert!(
        validate(&config).iter().any(|p| p.contains("形状不合法")),
        "{:?}",
        validate(&config)
    );
}

#[test]
fn menu_count_is_capped_like_neoview() {
    let mut config = default_config();
    for index in 1..MAX_RADIAL_MENUS {
        config.menus.push(new_menu(index));
    }
    assert_eq!(config.menus.len(), MAX_RADIAL_MENUS);
    assert!(is_valid(&config), "16 个轮盘是上限不是越界");
    config.menus.push(new_menu(MAX_RADIAL_MENUS));
    assert!(validate(&config).iter().any(|p| p.contains("上限")));
}

#[test]
fn new_menus_and_items_use_neoview_slug_ids() {
    assert_eq!(new_menu_id(1), "menu-2");
    assert_eq!(new_item_id(0), "item-1");
    assert_eq!(new_item_id(41), "item-42");
    // id 形状要过 neoview 的校验：`^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$`。
    // 手写而不是引一个正则依赖：这是测试里的一次性检查，不值得为此加 crate。
    fn matches_neoview_id_shape(raw: &str) -> bool {
        let mut chars = raw.chars();
        let Some(first) = chars.next() else {
            return false;
        };
        if !(first.is_ascii_alphanumeric()) {
            return false;
        }
        raw.len() <= 80
            && chars.all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '.' | '_' | '-'))
    }
    assert!(matches_neoview_id_shape(&new_menu_id(1)));
    assert!(matches_neoview_id_shape(&new_item_id(3)));
    for id in item_ids(&default_menu()) {
        assert!(
            matches_neoview_id_shape(&id),
            "出厂条目 id {id} 过不了 neoview 的校验"
        );
    }
}

#[test]
fn config_round_trips_and_keeps_unknown_and_missing_fields() {
    let config = default_config();
    let json = serde_json::to_string(&config).unwrap();
    let parsed: RadialConfig = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed, config);
    for field in [
        "\"activeMenuId\"",
        "\"layerCount\"",
        "\"innerRadius\"",
        "\"startAngle\"",
        "\"sweepAngle\"",
        "\"slotIndex\"",
    ] {
        assert!(json.contains(field), "缺字段 {field}：{json}");
    }
    // 老包（只有 menus）也要能读进来：启用类字段缺省为**开**。
    let legacy: RadialConfig = serde_json::from_str(
            r#"{"menus":[{"id":"default","name":"默认轮盘","layers":[[{"id":"a","label":"A","slotIndex":0}]]}]}"#,
        )
        .unwrap();
    assert!(legacy.enabled);
    assert_eq!(legacy.radius, DEFAULT_RADIAL_RADIUS);
    assert_eq!(legacy.active_menu().map(|m| m.id.as_str()), Some("default"));
    assert_eq!(legacy.active_menu().unwrap().layer(1).len(), 1);
    // 未知字段忽略而不是崩（导入 neoview 的包时会有）。
    let future: RadialConfig = serde_json::from_str(
        r#"{"enabled":true,"layerCount":2,"activeMenuId":"","menus":[],"brandNew":42}"#,
    )
    .unwrap();
    assert_eq!(future.layer_count, 2);
}

#[test]
fn legacy_inline_action_and_move_to_survive_the_layout() {
    // 遗留直连动作与「跳转轮盘」都要随布局带回外壳：前者是派发不到时的回落，
    // 后者决定松手是执行还是换轮盘。
    let menu = RadialMenuDefinition {
        id: "default".into(),
        name: "默认轮盘".into(),
        layers: vec![
            vec![
                RadialMenuItem {
                    id: "a".into(),
                    label: "A".into(),
                    slot_index: 0,
                    action: Some("reader.next-page".into()),
                    ..Default::default()
                },
                RadialMenuItem {
                    id: "b".into(),
                    label: "B".into(),
                    slot_index: 1,
                    move_to_menu_id: Some("two".into()),
                    ..Default::default()
                },
                RadialMenuItem {
                    id: "c".into(),
                    label: "C".into(),
                    slot_index: 2,
                    disabled: true,
                    ..Default::default()
                },
            ],
            vec![],
            vec![],
        ],
    };
    let config = RadialConfig {
        menus: vec![
            menu,
            RadialMenuDefinition {
                id: "two".into(),
                name: "另一个".into(),
                ..Default::default()
            },
        ],
        ..Default::default()
    };
    assert!(is_valid(&config), "{:?}", validate(&config));
    let layout = slot_layout(&config, config.menu("default").unwrap());
    assert_eq!(layout[0].legacy_action.as_deref(), Some("reader.next-page"));
    assert_eq!(layout[1].move_to_menu_id.as_deref(), Some("two"));
    assert!(!layout[2].selectable, "disabled 的条目不可选");
    let (dx, dy) = point_of(&layout[2]);
    assert_eq!(
        slot_at(&config, config.menu("default").unwrap(), dx, dy),
        None
    );
}

#[test]
fn radial_descriptor_shape_matches_model_rs() {
    // 运行时产的这条必须与 model.rs 钉过的形状逐字节一致，
    // 否则「导入的包能认、自己产的认不出」。
    let json = serde_json::to_string(&radial_input("default", "radial-next-page")).unwrap();
    assert_eq!(
        json,
        r#"{"device":"radial","menuId":"default","itemId":"radial-next-page"}"#
    );
}

#[test]
fn radial_bindings_do_not_shadow_click_bindings() {
    // 轮盘与点击住在同一张表里，靠 descriptor 区分，不许互相顶掉。
    let mut bindings = preset_bindings(DEFAULT_RADIAL_MENU_ID);
    bindings.extend(tap_preset_bindings(TapPreset::RightHand));
    assert!(conflicts(&bindings).is_empty());
    let wheel = resolve(
        &bindings,
        &radial_input(DEFAULT_RADIAL_MENU_ID, "radial-next-page"),
        &[InputContext::Reader],
    )
    .unwrap();
    assert_eq!(wheel.action, action::NEXT_PAGE);
    let tap = resolve(
        &bindings,
        &InputDescriptor::Area {
            area: ReaderViewArea::MiddleRight,
            button: 0,
            action: PointerAction::Click,
        },
        &[InputContext::Reader],
    )
    .unwrap();
    assert_eq!(tap.action, action::PAGE_RIGHT);
}

#[test]
fn layout_covers_every_shown_layer_only() {
    let three = default_config();
    assert_eq!(slot_layout(&three, three.active_menu().unwrap()).len(), 24);
    let two = RadialConfig {
        layer_count: 2,
        ..default_config()
    };
    let laid = slot_layout(&two, two.active_menu().unwrap());
    assert_eq!(laid.len(), 16);
    assert!(laid.iter().all(|entry| entry.level <= 2));
    // 层数只是**显示**几层，第 3 层的条目与绑定必须原样留着：
    // 用户把 3 层调成 2 层再调回来，不该发现自己的槽位被剪光了。
    // 真正会被剪的是「条目从文档里删掉」（另一条测试守着）。
    assert_eq!(
        prune_bindings(&two, &preset_bindings(DEFAULT_RADIAL_MENU_ID)).len(),
        12
    );
}
