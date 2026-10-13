use super::*;
use crate::operation_binding::{InputContext, InputDescriptor, resolve};
use serde_json::json;

fn row(id: &str, input: Value) -> Value {
    json!({"id": id, "action":"reader.toggle-controls", "enabled":false,
        "context":"reader", "ignoreRepeat":true, "followUpActions":["reader.zoom-in"],
        "extension":{"keep":true}, "input":input})
}

#[test]
fn migration_preserves_custom_rows_extensions_and_unique_ids() {
    let old = json!({"extension":"keep", "bindings":[
        row("custom", json!({"device":"area", "area":"middle-center", "button":0,
            "action":"click", "durationMs":700, "moveTolerancePx":9, "extra":42})),
        row("custom-touch", json!({"device":"touch", "gesture":"tap", "fingers":1})),
        row("right", json!({"device":"area", "area":"top-right", "button":2, "action":"press"})),
    ]});
    let doc = migrate(old).unwrap();
    assert_eq!(doc["extension"], "keep");
    assert_eq!(doc["bindings"].as_array().unwrap().len(), 4);
    assert_eq!(doc["bindings"][0]["input"]["device"], "mouse");
    let touch = &doc["bindings"][3];
    assert_eq!(touch["id"], "custom-touch-2");
    assert_eq!(touch["enabled"], false);
    assert_eq!(touch["ignoreRepeat"], true);
    assert_eq!(touch["followUpActions"], json!(["reader.zoom-in"]));
    assert_eq!(touch["input"]["durationMs"], 700);
    assert_eq!(touch["input"]["extra"], 42);
    assert_eq!(touch["input"]["area"], "middle-center");
    assert!(touch["input"].get("button").is_none());
    assert_eq!(migrate(doc.clone()).unwrap(), doc);
}

#[test]
fn empty_deleted_and_disabled_configs_never_gain_defaults() {
    assert_eq!(migrate(json!([])).unwrap()["bindings"], json!([]));
    let mut old: Vec<Value> = factory::input_bindings()
        .into_iter()
        .map(|row| serde_json::to_value(row).unwrap())
        .collect();
    for row in &mut old {
        if row["input"].get("area").is_some() {
            row["input"]["device"] = json!("area");
        }
    }
    old.retain(|row| row["input"]["area"] != "middle-left");
    old[0]["enabled"] = json!(false);
    let doc = migrate(json!(old)).unwrap();
    assert!(
        !doc["bindings"]
            .as_array()
            .unwrap()
            .iter()
            .any(|row| row["id"].as_str().unwrap().starts_with("default-touch-"))
    );
    assert_eq!(doc["bindings"][0]["enabled"], false);
    assert!(
        !doc["bindings"]
            .as_array()
            .unwrap()
            .iter()
            .any(|row| row["input"]["area"] == "middle-left" && row["context"] == "global")
    );
}

#[test]
fn untouched_neo_gets_independent_touch_defaults() {
    let mut old = serde_json::to_value(factory::input_bindings()).unwrap();
    for row in old.as_array_mut().unwrap() {
        if row["input"].get("area").is_some() {
            row["input"]["device"] = json!("area");
        }
    }
    let result = migrate_with_report(old).unwrap();
    let doc = result.document;
    let new_ids: Vec<_> = doc["bindings"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|row| row["id"].as_str())
        .filter(|id| id.starts_with("default-touch-"))
        .map(str::to_owned)
        .collect();
    assert_eq!(result.report.created_binding_ids, new_ids);
    let rows: Vec<InputBinding> = serde_json::from_value(doc["bindings"].clone()).unwrap();
    let touch: InputDescriptor = serde_json::from_value(
        json!({"device":"touch", "gesture":"tap", "fingers":1, "area":"middle-center"}),
    )
    .unwrap();
    assert_eq!(
        resolve::resolve(&rows, &touch, &[InputContext::Reader])
            .unwrap()
            .action,
        "reader.toggle-controls"
    );
    assert_eq!(migrate(doc.clone()).unwrap(), doc);
}

#[test]
fn runtime_only_accepts_v2_descriptors_and_document_rejects_future_versions() {
    assert!(
        serde_json::from_value::<InputDescriptor>(
            json!({"device":"area", "area":"middle-center", "button":0, "action":"click"})
        )
        .is_err()
    );
    for bad in [
        json!({"format":FORMAT,"format_version":3,"bindings":[]}),
        json!({"format":"other","bindings":[]}),
        json!({"format":FORMAT,"format_version":"2","bindings":[]}),
        json!({"format":FORMAT,"format_version":2,"bindings":[row("bad",json!({"device":"touch","fingers":0,"gesture":"tap"}))]}),
        json!({"bindings":[row("dup",json!({"device":"touch","fingers":1,"gesture":"tap"})),row("dup",json!({"device":"touch","fingers":1,"gesture":"tap"}))]}),
    ] {
        assert!(migrate(bad.clone()).is_err(), "{bad}");
    }
}

#[test]
fn region_is_more_specific_within_context_and_mouse_never_matches_touch() {
    let mut generic = row(
        "generic",
        json!({"device":"touch", "gesture":"tap", "fingers":1}),
    );
    generic["enabled"] = json!(true);
    let mut spatial = generic.clone();
    spatial["id"] = json!("spatial");
    spatial["action"] = json!("reader.page-left");
    spatial["input"]["area"] = json!("middle-left");
    let rows: Vec<InputBinding> = serde_json::from_value(json!([generic, spatial])).unwrap();
    let event: InputDescriptor = serde_json::from_value(
        json!({"device":"touch", "gesture":"tap", "fingers":1,"area":"middle-left"}),
    )
    .unwrap();
    assert_eq!(
        resolve::resolve(&rows, &event, &[InputContext::Reader])
            .unwrap()
            .id,
        "spatial"
    );
    assert!(resolve::conflicts(&rows).is_empty());
    let mouse = serde_json::from_value(
        json!({"device":"mouse", "action":"click", "button":0,"area":"middle-left"}),
    )
    .unwrap();
    assert!(resolve::resolve(&rows, &mouse, &[InputContext::Reader]).is_none());
    assert!(resolve::resolve(&rows, &event, &[InputContext::Modal]).is_none());
}
