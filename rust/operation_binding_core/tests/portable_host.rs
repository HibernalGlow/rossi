use operation_binding_core::{migration::*, resolve::*, *};
use serde_json::{Value, json};

fn doc() -> InputBindingsConfig {
    serde_json::from_str(include_str!("../examples/canvas_bindings.json")).unwrap()
}
fn input(device: &str, area: Option<&str>) -> InputDescriptor {
    let mut value = match device {
        "touch" => json!({"device":"touch","gesture":"tap","fingers":1}),
        _ => json!({"device":"mouse","action":"click","button":0}),
    };
    if let Some(area) = area {
        value["area"] = json!(area);
    }
    serde_json::from_value(value).unwrap()
}

#[test]
fn second_host_uses_custom_contexts_areas_and_actions() {
    let config = doc();
    config.validate().unwrap();
    let active = vec!["selection".into()];
    let touch = input("touch", Some("tool-palette"));
    let matched = resolve(&config.bindings, &touch, &config.contexts, &active).unwrap();
    assert_eq!(matched.action, "canvas.select-tool");
    let trace = diagnose(&config.bindings, &touch, &config.contexts, &active);
    assert_eq!(trace.binding_id.as_deref(), Some(matched.id.as_str()));
    assert!(trace.active_contexts.contains(&"canvas".into()));
    assert!(
        trace
            .candidates
            .iter()
            .any(|row| row.binding_id == "canvas-tap"
                && row.outcome == CandidateOutcome::LessSpecific)
    );
    let generic = input("touch", Some("custom-other-zone"));
    assert_eq!(
        resolve(&config.bindings, &generic, &config.contexts, &active)
            .unwrap()
            .action,
        "canvas.inspect"
    );
    assert_eq!(
        resolve(
            &config.bindings,
            &input("mouse", Some("tool-palette")),
            &config.contexts,
            &active
        )
        .unwrap()
        .action,
        "canvas.draw"
    );
    assert!(
        resolve(
            &config.bindings,
            &input("mouse", None),
            &config.contexts,
            &active
        )
        .is_none()
    );
}

#[test]
fn modal_isolation_and_context_precedence_are_explicit() {
    let mut config = doc();
    let mut override_row = config.bindings[0].clone();
    override_row.id = "selection-override".into();
    override_row.context = "selection".into();
    override_row.action = "selection.inspect".into();
    config.bindings.push(override_row);
    assert_eq!(
        resolve(
            &config.bindings,
            &input("touch", Some("tool-palette")),
            &config.contexts,
            &["selection".into()]
        )
        .unwrap()
        .action,
        "selection.inspect",
        "context priority precedes area specificity"
    );
    let key = serde_json::from_value(json!({"device":"keyboard","code":"KeyO"})).unwrap();
    assert!(resolve(&config.bindings, &key, &config.contexts, &[]).is_some());
    let trace = diagnose(&config.bindings, &key, &config.contexts, &["rename".into()]);
    assert!(trace.binding_id.is_none());
    assert!(
        trace
            .candidates
            .iter()
            .any(|row| row.binding_id == "app-open"
                && row.outcome == CandidateOutcome::IsolatedGlobal)
    );
}

#[test]
fn conflicts_reject_exact_overlaps_and_equal_priority_context_ties() {
    let mut config = doc();
    assert!(conflicts_with_contexts(&config.bindings, &config.contexts).is_empty());
    let mut duplicate = config.bindings[1].clone();
    duplicate.id = "duplicate".into();
    config.bindings.push(duplicate.clone());
    assert_eq!(
        conflicts(&config.bindings)[0].binding_ids,
        vec!["canvas-tool", "duplicate"]
    );
    config.bindings.pop();
    let mut peer = config.contexts[1].clone();
    peer.id = "peer".into();
    config.contexts.push(peer);
    duplicate.context = "peer".into();
    config.bindings.push(duplicate);
    assert_eq!(
        conflicts_with_contexts(&config.bindings, &config.contexts).len(),
        1
    );
    config.bindings.last_mut().unwrap().enabled = false;
    assert!(conflicts_with_contexts(&config.bindings, &config.contexts).is_empty());
}

#[test]
fn stable_json_protocol_is_identical_for_rust_and_json_hosts() {
    let config = doc();
    let event = input("touch", Some("tool-palette"));
    let active = vec!["canvas".into()];
    let before = diagnose(&config.bindings, &event, &config.contexts, &active);
    let raw = serde_json::to_string(&config).unwrap();
    let migrated = migrate_json(&raw).unwrap();
    let parsed: InputBindingsConfig = serde_json::from_value(migrated.document).unwrap();
    let after = diagnose(&parsed.bindings, &event, &parsed.contexts, &active);
    assert_eq!(
        serde_json::to_value(before).unwrap(),
        serde_json::to_value(after).unwrap()
    );
    assert!(migrated.report.created_binding_ids.is_empty());
}

#[test]
fn migration_is_lossless_idempotent_and_reports_transformed_rows() {
    let old = json!({"extra":"keep", "bindings":[{"id":"old", "action":"canvas.select", "context":"canvas", "enabled":false,
        "ignoreRepeat":true, "followUpActions":["canvas.inspect"], "input":{"device":"area","button":0,"action":"click","area":"free-form-zone", "durationMs":810}}]});
    let result = migrate_with_report(old).unwrap();
    assert_eq!(result.report.converted_binding_ids, vec!["old"]);
    assert_eq!(result.report.created_binding_ids, vec!["old-touch"]);
    assert_eq!(result.document["extra"], "keep");
    let touch = &result.document["bindings"][1];
    assert_eq!(touch["enabled"], false);
    assert_eq!(touch["input"]["durationMs"], 810);
    assert_eq!(touch["followUpActions"], json!(["canvas.inspect"]));
    assert_eq!(migrate(result.document.clone()).unwrap(), result.document);
    assert_eq!(migrate(json!([])).unwrap()["bindings"], json!([]));
}

#[test]
fn invalid_versions_inputs_and_context_graphs_fail_without_modifying_document() {
    let future = json!({"format":FORMAT,"format_version":99,"bindings":[]});
    assert!(migrate(future).is_err());
    let mut config = doc();
    config.contexts[1].parent = Some("selection".into());
    assert!(config.validate().is_err());
    config.contexts[1].parent = Some("missing".into());
    assert!(config.validate().is_err());
    let mut value = serde_json::to_value(doc()).unwrap();
    value["bindings"][0]["input"]["area"] = json!("");
    assert!(migrate(value).is_err());
    let invalid: Value = json!({"format":FORMAT,"format_version":2,"bindings":[{"id":"invalid","action":"x","context":"x","enabled":true,"input":{"device":"touch","gesture":"double-tap","fingers":2}}]});
    assert!(migrate(invalid).is_err());
}
