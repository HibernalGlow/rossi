//! Framework-independent operation bindings. The host owns event collection,
//! hit testing, context activation, action metadata and execution.
//! Only serde, serde_json and anyhow are required; no Flutter or application dependency.
pub mod context;
pub mod descriptor;
pub mod migration;
pub mod model;
pub mod resolve;

pub use context::ContextDefinition;
pub use model::{InputBinding, InputBindingsConfig, InputDescriptor};
pub use resolve::{conflicts, diagnose, resolve};
