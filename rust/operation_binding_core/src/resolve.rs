use crate::{ContextDefinition, InputBinding, InputDescriptor, context, descriptor};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InputConflict {
    pub key: String,
    pub binding_ids: Vec<String>,
}

pub fn conflict_key(context: &str, input: &InputDescriptor) -> String {
    // Encode both dimensions independently; separators inside a host area id cannot collide.
    serde_json::to_string(&(context, input)).expect("Input descriptor is serializable")
}

pub fn conflicts(bindings: &[InputBinding]) -> Vec<InputConflict> {
    let mut groups: Vec<InputConflict> = Vec::new();
    for row in bindings.iter().filter(|row| row.enabled) {
        let key = conflict_key(&row.context, &row.input);
        if let Some(group) = groups.iter_mut().find(|group| group.key == key) {
            group.binding_ids.push(row.id.clone());
        } else {
            groups.push(InputConflict {
                key,
                binding_ids: vec![row.id.clone()],
            });
        }
    }
    groups
        .into_iter()
        .filter(|group| group.binding_ids.len() > 1)
        .collect()
}

/// Detect equally specific rules in different contexts with equal priority as well.
/// Without exclusivity metadata those contexts may be active together, so save must reject ties.
pub fn conflicts_with_contexts(
    bindings: &[InputBinding],
    definitions: &[ContextDefinition],
) -> Vec<InputConflict> {
    let mut result = conflicts(bindings);
    for (index, left) in bindings.iter().enumerate().filter(|(_, row)| row.enabled) {
        for right in bindings[index + 1..].iter().filter(|row| row.enabled) {
            if left.context == right.context || left.input != right.input {
                continue;
            }
            let l = definitions.iter().find(|def| def.id == left.context);
            let r = definitions.iter().find(|def| def.id == right.context);
            if l.zip(r).is_some_and(|(l, r)| l.priority == r.priority) {
                result.push(InputConflict {
                    key: format!("equal-priority:{}:{}", left.context, right.context),
                    binding_ids: vec![left.id.clone(), right.id.clone()],
                });
            }
        }
    }
    result
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum CandidateOutcome {
    Disabled,
    UnknownContext,
    InactiveContext,
    IsolatedGlobal,
    InputMismatch,
    LowerPriority,
    LessSpecific,
    Tied,
    Matched,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CandidateDiagnostic {
    pub binding_id: String,
    pub context: String,
    pub outcome: CandidateOutcome,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MatchDiagnostic {
    pub input: InputDescriptor,
    pub active_contexts: Vec<String>,
    pub binding_id: Option<String>,
    pub action: Option<String>,
    pub candidates: Vec<CandidateDiagnostic>,
}

fn rank(
    row: &InputBinding,
    input: &InputDescriptor,
    definitions: &[ContextDefinition],
    active: &[&ContextDefinition],
) -> Result<(i32, bool), CandidateOutcome> {
    if !row.enabled {
        return Err(CandidateOutcome::Disabled);
    }
    let Some(def) = definitions.iter().find(|def| def.id == row.context) else {
        return Err(CandidateOutcome::UnknownContext);
    };
    if def.global {
        if active.iter().any(|def| def.isolates_global) {
            return Err(CandidateOutcome::IsolatedGlobal);
        }
    } else if !active.iter().any(|active| active.id == def.id) {
        return Err(CandidateOutcome::InactiveContext);
    }
    if !descriptor::matches(&row.input, input) {
        return Err(CandidateOutcome::InputMismatch);
    }
    Ok((def.priority, descriptor::area(&row.input).is_some()))
}

/// Context priority first, then specificity. First row wins only as deterministic recovery
/// for an already conflicting document; editors must reject conflicts before saving.
pub fn resolve<'a>(
    bindings: &'a [InputBinding],
    input: &InputDescriptor,
    definitions: &[ContextDefinition],
    active: &[String],
) -> Option<&'a InputBinding> {
    let active = context::active_contexts(definitions, active);
    let mut matched = None;
    let mut best = (i32::MIN, false);
    for row in bindings {
        if let Ok(priority) = rank(row, input, definitions, &active) {
            if matched.is_none() || priority > best {
                best = priority;
                matched = Some(row);
            }
        }
    }
    matched
}

/// Pure diagnostic output uses the same candidate/ranking functions as normal resolution.
pub fn diagnose(
    bindings: &[InputBinding],
    input: &InputDescriptor,
    definitions: &[ContextDefinition],
    active: &[String],
) -> MatchDiagnostic {
    let matched = resolve(bindings, input, definitions, active);
    let active = context::active_contexts(definitions, active);
    let best = matched.map(|row| rank(row, input, definitions, &active).unwrap());
    let candidates = bindings
        .iter()
        .map(|row| {
            let outcome = match rank(row, input, definitions, &active) {
                Err(reason) => reason,
                Ok(_) if matched.is_some_and(|matched| matched.id == row.id) => {
                    CandidateOutcome::Matched
                }
                Ok(priority) if best.is_some_and(|best| priority.0 < best.0) => {
                    CandidateOutcome::LowerPriority
                }
                Ok(priority) if best.is_some_and(|best| priority.1 < best.1) => {
                    CandidateOutcome::LessSpecific
                }
                Ok(_) => CandidateOutcome::Tied,
            };
            CandidateDiagnostic {
                binding_id: row.id.clone(),
                context: row.context.clone(),
                outcome,
            }
        })
        .collect();
    MatchDiagnostic {
        input: input.clone(),
        active_contexts: active.iter().map(|def| def.id.clone()).collect(),
        binding_id: matched.map(|row| row.id.clone()),
        action: matched.map(|row| row.action.clone()),
        candidates,
    }
}
