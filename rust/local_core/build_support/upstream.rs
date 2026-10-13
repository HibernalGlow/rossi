//! 从固定子模块的 Rust AST 选取纯逻辑；不保存另一份函数体。
use quote::ToTokens;
use serde_json::Value;
use syn::visit_mut::VisitMut;
use syn::{Item, Visibility};

struct CrateVisibility;
impl VisitMut for CrateVisibility {
    fn visit_visibility_mut(&mut self, visibility: &mut Visibility) {
        if matches!(visibility, Visibility::Restricted(r) if r.path.is_ident("crate")) {
            *visibility = Visibility::Public(Default::default());
        }
    }
}

fn key(item: &Item) -> Option<String> {
    Some(match item {
        Item::Fn(i) => format!("fn {}", i.sig.ident),
        Item::Enum(i) => format!("enum {}", i.ident),
        Item::Struct(i) => format!("struct {}", i.ident),
        Item::Const(i) => format!("const {}", i.ident),
        Item::Impl(i) => match &i.trait_ {
            Some((_, path, _)) => format!(
                "impl {} for {}",
                path.to_token_stream(),
                i.self_ty.to_token_stream()
            ),
            None => format!("impl {}", i.self_ty.to_token_stream()),
        },
        _ => return None,
    })
}

fn compact(s: &str) -> String {
    s.chars().filter(|c| !c.is_whitespace()).collect()
}

fn listed(spec: &Value, field: &str, marker: &str) -> bool {
    spec[field]
        .as_array()
        .is_some_and(|items| items.iter().any(|v| v.as_str() == Some(marker)))
}

pub fn extract(source: &str, spec: &Value) -> Result<String, String> {
    let parsed = syn::parse_file(source).map_err(|e| format!("上游语法无法解析：{e}"))?;
    let mut selected = Vec::new();
    if spec["whole_file"].as_bool() == Some(true) {
        selected = parsed.items.clone();
        if let Some(omitted) = spec["omit_items"].as_array() {
            for marker in omitted {
                let marker = marker.as_str().ok_or("omit_items 必须为符号字符串")?;
                let before = selected.len();
                selected.retain(|i| !key(i).is_some_and(|k| compact(&k) == compact(marker)));
                if before != selected.len() + 1 {
                    return Err(format!("排除符号 {marker} 必须唯一"));
                }
            }
        }
        for item in &mut selected {
            CrateVisibility.visit_item_mut(item);
        }
    } else {
        for marker in spec["items"].as_array().ok_or("缺少 items")? {
            let marker = marker.as_str().ok_or("items 必须为符号字符串")?;
            let candidates: Vec<_> = parsed
                .items
                .iter()
                .filter(|i| key(i).is_some_and(|k| compact(&k) == compact(marker)))
                .collect();
            if candidates.len() != 1 {
                return Err(format!(
                    "{marker} 必须唯一，实际 {} 项；请复核上游接口变化",
                    candidates.len()
                ));
            }
            let mut item = candidates[0].clone();
            // 只修改边界：公开可见性、字段可见性或显式排除的未接入方法。
            // 函数体和 derives 完整使用上游 AST。
            if listed(spec, "public", marker) {
                let vis = match &mut item {
                    Item::Fn(i) => &mut i.vis,
                    Item::Struct(i) => &mut i.vis,
                    Item::Enum(i) => &mut i.vis,
                    _ => return Err(format!("{marker} 不支持公开适配")),
                };
                *vis = Visibility::Public(Default::default());
            }
            if listed(spec, "fields_public", marker) {
                let Item::Struct(i) = &mut item else {
                    return Err("fields_public 只能用于 struct".into());
                };
                for field in &mut i.fields {
                    field.vis = Visibility::Public(Default::default());
                }
            }
            if let Some(omitted) = spec["omit_methods"][marker].as_array() {
                let Item::Impl(i) = &mut item else {
                    return Err("omit_methods 只能用于 impl".into());
                };
                for name in omitted {
                    let name = name.as_str().ok_or("方法名必须为字符串")?;
                    let before = i.items.len();
                    i.items
                        .retain(|m| !matches!(m, syn::ImplItem::Fn(f) if f.sig.ident == name));
                    if before == i.items.len() {
                        return Err(format!("未找到排除方法 {marker}::{name}"));
                    }
                }
            }
            selected.push(item);
        }
    }
    let file = syn::File {
        shebang: None,
        attrs: vec![],
        items: selected,
    };
    Ok(format!(
        "// Copyright (c) 2026 SANO Taku (Mikage Sawatari), MIT.\n// Generated from vendor/mimageviewer/{}; do not edit.\n{}",
        spec["upstream"].as_str().ok_or("缺少 upstream")?,
        prettyplease::unparse(&file)
    ))
}
