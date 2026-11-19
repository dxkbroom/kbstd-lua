//! Convenience constructors for [`PermissionsContainer`].
//!
//! Hosts with their own policy build the container directly through
//! [`deno_permissions`]; these cover the common cases and tests.

use std::sync::Arc;

use deno_permissions::{Permissions, PermissionsContainer, RuntimePermissionDescriptorParser};
use sys_traits::impls::RealSys;

fn parser() -> Arc<RuntimePermissionDescriptorParser<RealSys>> {
    Arc::new(RuntimePermissionDescriptorParser::new(RealSys))
}

/// Permissions that grant every access.
pub fn allow_all() -> PermissionsContainer {
    PermissionsContainer::allow_all(parser())
}

/// Permissions that grant nothing and never prompt.
pub fn deny_all() -> PermissionsContainer {
    PermissionsContainer::new(parser(), Permissions::none_without_prompt())
}
