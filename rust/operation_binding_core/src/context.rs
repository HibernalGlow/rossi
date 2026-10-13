use anyhow::{Result, ensure};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

/// Context names, priorities and ancestry are application data.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContextDefinition {
    pub id: String,
    pub priority: i32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent: Option<String>,
    #[serde(default)]
    pub global: bool,
    #[serde(default)]
    pub isolates_global: bool,
}

pub fn validate(definitions: &[ContextDefinition]) -> Result<()> {
    let mut ids = HashSet::new();
    for def in definitions {
        ensure!(
            !def.id.trim().is_empty() && ids.insert(&def.id),
            "Empty or duplicate context: {}",
            def.id
        );
    }
    for def in definitions {
        let mut seen = HashSet::new();
        let mut current = def;
        while let Some(parent) = &current.parent {
            ensure!(
                seen.insert(&current.id),
                "Context ancestry cycle: {}",
                def.id
            );
            current = definitions
                .iter()
                .find(|def| &def.id == parent)
                .ok_or_else(|| anyhow::anyhow!("Unknown parent context: {parent}"))?;
        }
    }
    Ok(())
}

/// A focused descendant also activates its ancestors. Unknown ids are ignored.
pub fn active_contexts<'a>(
    definitions: &'a [ContextDefinition],
    active: &[String],
) -> Vec<&'a ContextDefinition> {
    let mut result = Vec::new();
    for id in active {
        let mut current = definitions.iter().find(|def| &def.id == id);
        while let Some(def) = current {
            if result
                .iter()
                .any(|existing: &&ContextDefinition| existing.id == def.id)
            {
                break;
            }
            result.push(def);
            current = def
                .parent
                .as_ref()
                .and_then(|parent| definitions.iter().find(|def| &def.id == parent));
        }
    }
    result
}
