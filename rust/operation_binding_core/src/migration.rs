//! 历史格式只在启动、同步/恢复与导入边界升级；运行时模型只认识当前 schema。
//! 直接修改 JSON Value，保留动作序列、时序参数及未知扩展字段。

use std::collections::HashSet;

use anyhow::{Context, Result, bail, ensure};
use serde_json::{Value, json};

use crate::{InputBinding, InputBindingsConfig, model};

pub const FORMAT: &str = "operation-bindings";
pub const CURRENT_VERSION: u32 = 2;

pub fn migrate_json(raw: &str) -> Result<MigrationResult> {
    let value: Value = serde_json::from_str(raw).context("操作绑定 JSON 无法解析")?;
    migrate_with_report(value)
}

pub fn migrate(value: Value) -> Result<Value> {
    let (mut doc, version) = match value {
        Value::Array(rows) => (json!({"bindings": rows}), 1),
        Value::Object(doc) => {
            if let Some(format) = doc.get("format") {
                ensure!(format.as_str() == Some(FORMAT), "未知的操作绑定文档格式");
            }
            let version = match doc.get("format_version") {
                None => 1,
                Some(version) => version.as_u64().context("操作绑定版本号无效")?,
            };
            (Value::Object(doc), version)
        }
        _ => bail!("操作绑定必须是文档或数组"),
    };
    ensure!(
        (1..=CURRENT_VERSION as u64).contains(&version),
        "不支持的操作绑定版本：{version}"
    );
    if version == 1 {
        let rows = doc["bindings"]
            .as_array()
            .context("操作绑定缺少 bindings 数组")?;
        doc["bindings"] = Value::Array(migrate_v1_to_v2(rows)?);
    } else {
        ensure!(
            doc["format"].as_str() == Some(FORMAT),
            "操作绑定缺少格式标识"
        );
    }
    doc["format"] = json!(FORMAT);
    doc["format_version"] = json!(CURRENT_VERSION);
    let parsed: Vec<InputBinding> = serde_json::from_value(doc["bindings"].clone())
        .context("操作绑定的输入、动作或上下文无效")?;
    ensure!(
        model::bindings_are_valid(&parsed),
        "操作绑定含无效参数或重复 id"
    );
    let config: InputBindingsConfig = serde_json::from_value(doc.clone())?;
    if !config.contexts.is_empty() {
        crate::context::validate(&config.contexts)?;
        ensure!(
            config
                .bindings
                .iter()
                .all(|row| config.contexts.iter().any(|def| def.id == row.context)),
            "Unknown binding context"
        );
    }
    Ok(doc)
}

pub fn migrate_v1_to_v2(rows: &[Value]) -> Result<Vec<Value>> {
    let mut mouse_rows = rows.to_vec();
    let mut touch_rows = Vec::new();
    let mut ids: HashSet<String> = rows
        .iter()
        .filter_map(|row| row["id"].as_str().map(str::to_owned))
        .collect();
    for row in &mut mouse_rows {
        if row["input"]["device"] != "area" {
            continue;
        }
        // 旧 area 只有主键单击会被触屏采集器产出。中/右键、按下/长按/双击
        // 从来不是触屏输入，不能凭空把它们变成新的触屏动作。
        let input = row["input"].as_object_mut().context("旧区域输入无效")?;
        ensure!(
            input
                .get("button")
                .and_then(Value::as_u64)
                .is_some_and(|button| button < 3),
            "旧区域鼠标按钮无效"
        );
        input.insert("device".into(), json!("mouse"));
        if input.get("button") == Some(&json!(0)) && input.get("action") == Some(&json!("click")) {
            let mut touch = row.clone();
            let base = format!("{}-touch", row["id"].as_str().context("旧绑定缺少 id")?);
            let mut id = base.clone();
            let mut suffix = 2;
            while !ids.insert(id.clone()) {
                id = format!("{base}-{suffix}");
                suffix += 1;
            }
            touch["id"] = json!(id);
            let input = touch["input"].as_object_mut().unwrap();
            input.insert("device".into(), json!("touch"));
            input.remove("button");
            input.remove("action");
            input.insert("gesture".into(), json!("tap"));
            input.insert("fingers".into(), json!(1));
            touch_rows.push(touch);
        }
    }
    mouse_rows.extend(touch_rows);
    Ok(mouse_rows)
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MigrationReport {
    pub from_version: u32,
    pub to_version: u32,
    pub converted_binding_ids: Vec<String>,
    pub created_binding_ids: Vec<String>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct MigrationResult {
    pub document: Value,
    pub report: MigrationReport,
}

pub fn migrate_with_report(value: Value) -> Result<MigrationResult> {
    let from_version = value
        .get("format_version")
        .and_then(Value::as_u64)
        .unwrap_or(1) as u32;
    let old_rows = if value.is_array() {
        value.as_array()
    } else {
        value.get("bindings").and_then(Value::as_array)
    };
    let old_ids: HashSet<String> = old_rows
        .into_iter()
        .flatten()
        .filter_map(|row| row["id"].as_str().map(str::to_owned))
        .collect();
    let converted_binding_ids = if from_version == 1 {
        old_rows
            .into_iter()
            .flatten()
            .filter(|row| row["input"]["device"] == "area")
            .filter_map(|row| row["id"].as_str().map(str::to_owned))
            .collect()
    } else {
        Vec::new()
    };
    let document = migrate(value)?;
    let created_binding_ids = document["bindings"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|row| row["id"].as_str())
        .filter(|id| !old_ids.contains(*id))
        .map(str::to_owned)
        .collect();
    Ok(MigrationResult {
        document,
        report: MigrationReport {
            from_version,
            to_version: CURRENT_VERSION,
            converted_binding_ids,
            created_binding_ids,
        },
    })
}
