//! Embedding runtime for luastd.
//!
//! Skeleton for now: it re-exports the pinned `mlua` so hosts and luastd agree
//! on one version. The builder, effect modules and async land in later layers
//! (see `PLAN.md`).

pub use luastd;
pub use mlua;
