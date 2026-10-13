//! 验证更新会进入产物，符号消失/重名会阻止构建，适配不修改函数体。
#[path = "../build_support/upstream.rs"]
mod upstream;

use serde_json::json;

#[test]
fn source_changes_are_consumed_without_a_local_function_copy() {
    let spec =
        json!({"upstream": "src/policy.rs", "items": ["fn budget"], "public": ["fn budget"]});
    let old = upstream::extract("pub(crate) fn budget() -> u32 { 6 }", &spec).unwrap();
    let new = upstream::extract("pub(crate) fn budget() -> u32 { 9 }", &spec).unwrap();
    assert!(old.contains("    6"));
    assert!(new.contains("    9"));
    assert!(new.contains("pub fn budget"));
    assert!(!new.contains("pub(crate)"));
}

#[test]
fn renamed_or_ambiguous_source_symbols_fail_closed() {
    let spec = json!({"upstream": "src/policy.rs", "items": ["fn budget"]});
    assert!(upstream::extract("fn new_budget() {}", &spec).is_err());
    assert!(upstream::extract("fn budget() {} fn budget() {}", &spec).is_err());
}

#[test]
fn ast_selection_handles_literal_braces_and_retains_type_attributes() {
    let spec = json!({"upstream": "src/policy.rs", "items": ["struct Policy", "impl Policy"],
        "omit_methods": {"impl Policy": ["ui_only"]}});
    let source = r##"
        #[derive(Clone, Debug)] struct Policy { size: u32 }
        impl Policy {
            fn ui_only() { /* } */ }
            fn retained() -> &'static str { r#"{ not a body }"# }
        }
    "##;
    let result = upstream::extract(source, &spec).unwrap();
    assert!(result.contains("derive(Clone, Debug)"));
    assert!(result.contains("{ not a body }"));
    assert!(result.contains("retained"));
    assert!(!result.contains("ui_only"));
    let invalid = json!({"upstream": "x.rs", "items": ["impl Policy"], "omit_methods": {"impl Policy": ["missing"]}});
    assert!(upstream::extract(source, &invalid).is_err());
}

#[test]
fn tile_fields_are_exposed_without_rewriting_layout() {
    let spec = json!({"upstream": "x.rs", "items": ["struct Tile"], "public": ["struct Tile"], "fields_public": ["struct Tile"]});
    let result =
        upstream::extract("#[derive(Clone)] struct Tile { x: u32, y: u32 }", &spec).unwrap();
    assert!(result.contains("pub struct Tile"));
    assert!(result.contains("pub x: u32"));
    assert!(result.contains("pub y: u32"));
}

#[test]
fn whole_pure_module_includes_new_functions_and_promotes_crate_visibility() {
    let spec = json!({"upstream": "policy.rs", "whole_file": true});
    let result = upstream::extract("pub(crate) struct State { pub(crate) budget: u32 }\nimpl State { pub(crate) fn new() -> Self { Self { budget: 6 } } }\npub(crate) fn added_later() {}", &spec).unwrap();
    assert!(result.contains("pub struct State"));
    assert!(result.contains("pub budget: u32"));
    assert!(result.contains("pub fn new"));
    assert!(result.contains("pub fn added_later"));
    assert!(!result.contains("pub(crate)"));
    let excluded =
        json!({"upstream": "policy.rs", "whole_file": true, "omit_items": ["fn platform_root"]});
    let result =
        upstream::extract("fn platform_root() {} pub(crate) fn shared() {}", &excluded).unwrap();
    assert!(!result.contains("platform_root"));
    assert!(result.contains("pub fn shared"));
    assert!(upstream::extract("fn shared() {}", &excluded).is_err());
}
