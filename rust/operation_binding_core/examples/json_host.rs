//! Minimal non-Flutter host. Optional argv[1] is any exported bindings document;
//! argv[2] is an input descriptor JSON and remaining args are active context ids.
use anyhow::{Context, Result, ensure};
use operation_binding_core::{
    InputBindingsConfig, InputDescriptor, diagnose, migration, resolve::conflicts_with_contexts,
};
use serde_json::json;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let raw = args
        .first()
        .map(std::fs::read_to_string)
        .transpose()?
        .unwrap_or_else(|| include_str!("canvas_bindings.json").into());
    let migration = migration::migrate_json(&raw)?;
    let config: InputBindingsConfig = serde_json::from_value(migration.document)?;
    config.validate()?;
    ensure!(
        conflicts_with_contexts(&config.bindings, &config.contexts).is_empty(),
        "Conflicting bindings"
    );
    let input: InputDescriptor = serde_json::from_str(
        args.get(1)
            .map(String::as_str)
            .unwrap_or(r#"{"device":"touch","gesture":"tap","fingers":1,"area":"tool-palette"}"#),
    )
    .context("Input descriptor")?;
    let active = if args.len() > 2 {
        args[2..].to_vec()
    } else {
        vec!["selection".into()]
    };
    println!(
        "{}",
        serde_json::to_string_pretty(&json!({
            "migration": migration.report,
            "result": diagnose(&config.bindings, &input, &config.contexts, &active)
        }))?
    );
    Ok(())
}
