//! Rossi 的历史默认值适配。协议迁移和校验均调用公共核心。
use super::{InputBinding, factory, resolve};
use anyhow::Result;
pub use operation_binding_core::migration::{CURRENT_VERSION, FORMAT};
use serde_json::Value;

pub fn migrate_json(raw: &str) -> Result<String> {
    let result = migrate_with_report(serde_json::from_str(raw)?)?;
    Ok(serde_json::to_string(&result.document)?)
}

pub fn migrate(value: Value) -> Result<Value> {
    Ok(migrate_with_report(value)?.document)
}

pub fn migrate_with_report(
    value: Value,
) -> Result<operation_binding_core::migration::MigrationResult> {
    let old_rows = if value.is_array() {
        value.as_array()
    } else {
        value["bindings"].as_array()
    };
    let old_ids: std::collections::HashSet<String> = old_rows
        .into_iter()
        .flatten()
        .filter_map(|row| row["id"].as_str().map(str::to_owned))
        .collect();
    let mut result = operation_binding_core::migration::migrate_with_report(value)?;
    if result.report.from_version == 1 {
        let rows = result.document["bindings"].as_array().unwrap();
        let (mut original, mut created): (Vec<Value>, Vec<Value>) =
            rows.iter().cloned().partition(|row| {
                !result
                    .report
                    .created_binding_ids
                    .iter()
                    .any(|id| row["id"].as_str() == Some(id.as_str()))
            });
        if let Some(upgraded) = factory::upgrade_defaults(&original) {
            original = upgraded;
        }
        if is_untouched_neo(&original) {
            created = factory::touch_bindings()
                .into_iter()
                .map(|row| serde_json::to_value(row).unwrap())
                .collect();
        }
        original.extend(created);
        result.document["bindings"] = Value::Array(original);
        result.document["contexts"] = serde_json::to_value(resolve::context_definitions())?;
        result.document = operation_binding_core::migration::migrate(result.document)?;
    }
    result.report.created_binding_ids = result.document["bindings"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|row| row["id"].as_str())
        .filter(|id| !old_ids.contains(*id))
        .map(str::to_owned)
        .collect();
    Ok(result)
}

fn is_untouched_neo(rows: &[Value]) -> bool {
    let expected = factory::input_bindings();
    let mut actual = Vec::new();
    for raw in rows {
        if raw["input"]["device"] == "radial" {
            continue;
        }
        let Ok(row) = serde_json::from_value::<InputBinding>(raw.clone()) else {
            return false;
        };
        let normalized = serde_json::to_value(&row).unwrap();
        if !factory::known_fields_only(raw, &normalized) {
            return false;
        }
        actual.push(row);
    }
    actual.len() == expected.len() && actual.iter().all(|row| expected.contains(row))
}

#[cfg(test)]
mod tests;
