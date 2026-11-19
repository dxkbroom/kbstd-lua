//! The `luastd.semver` Lua module.
//!
//! Wraps the `semver` crate. Construct with `semver.new`, `semver.parse` or
//! `semver.default`. Values are Lua userdata with read-only fields, methods,
//! `tostring`, and comparison operators. Equality and ordering use SemVer
//! precedence, so build metadata is ignored.

use std::cmp::Ordering;
use std::fmt;
use std::hash::{Hash, Hasher};
use std::str::FromStr;

use ::semver::{BuildMetadata, Prerelease, Version as SemverVersion, VersionReq};
use mlua::prelude::*;
use mlua::{Table, UserData};

use crate::Module;
use crate::util::string_argument;

pub const TYPE_NAME: &str = "luastd.semver.Version";

/// The `luastd.semver` module.
pub struct Semver;

impl Module for Semver {
    const NAME: &'static str = "luastd.semver";

    fn create(lua: &Lua) -> LuaResult<Table> {
        let module = lua.create_table()?;
        module.set(
            "new",
            lua.create_function(|_, (major, minor, patch, pre, build): VersionNewArgs| {
                Version::lua_new(major, minor, patch, pre, build)
            })?,
        )?;
        module.set(
            "parse",
            lua.create_function(|_, version: LuaValue| {
                Version::lua_parse(&string_argument(&version, 1, "version", "parse")?)
            })?,
        )?;
        module.set(
            "default",
            lua.create_function(|_, ()| Ok(Version::default()))?,
        )?;
        module.set("valid", lua.create_function(semver_valid)?)?;
        Ok(module)
    }
}

/// A semantic version exposed to Lua.
#[derive(Clone, Debug)]
pub struct Version(SemverVersion);

impl Default for Version {
    fn default() -> Self {
        Self(SemverVersion::new(0, 0, 0))
    }
}

impl fmt::Display for Version {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(formatter)
    }
}

impl FromStr for Version {
    type Err = ::semver::Error;

    fn from_str(version: &str) -> Result<Self, Self::Err> {
        SemverVersion::parse(version).map(Self)
    }
}

impl PartialEq for Version {
    fn eq(&self, other: &Self) -> bool {
        self.cmp(other) == Ordering::Equal
    }
}

impl Eq for Version {}

impl PartialOrd for Version {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Version {
    fn cmp(&self, other: &Self) -> Ordering {
        self.0.cmp_precedence(&other.0)
    }
}

impl Hash for Version {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.0.major.hash(state);
        self.0.minor.hash(state);
        self.0.patch.hash(state);
        self.0.pre.hash(state);
    }
}

impl UserData for Version {
    fn add_fields<F: LuaUserDataFields<Self>>(fields: &mut F) {
        fields.add_meta_field(LuaMetaMethod::Type, TYPE_NAME);
        fields.add_field_method_get("major", |_, this| Ok(this.0.major));
        fields.add_field_method_get("minor", |_, this| Ok(this.0.minor));
        fields.add_field_method_get("patch", |_, this| Ok(this.0.patch));
        fields.add_field_method_get("pre", |_, this| Ok(this.0.pre.to_string()));
        fields.add_field_method_get("build", |_, this| Ok(this.0.build.to_string()));
    }

    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        // `Version:cmp(other) -> integer`
        methods.add_method("cmp", |_, this, other: LuaUserDataRef<Version>| {
            Ok(match this.cmp(&other) {
                Ordering::Less => -1,
                Ordering::Equal => 0,
                Ordering::Greater => 1,
            })
        });

        // `Version:satisfies(requirement) -> boolean`
        methods.add_method("satisfies", |_, this, requirement: LuaValue| {
            let requirement = string_argument(&requirement, 2, "requirement", "satisfies")?;
            let requirement = VersionReq::parse(&requirement)
                .map_err(|error| LuaError::runtime(format!("invalid requirement: {error}")))?;
            Ok(requirement.matches(&this.0))
        });

        methods.add_meta_method(LuaMetaMethod::ToString, |_, this, ()| Ok(this.to_string()));
        methods.add_meta_method(LuaMetaMethod::Eq, |_, this, other: LuaValue| {
            Ok(other
                .as_userdata()
                .and_then(|userdata| userdata.borrow::<Version>().ok())
                .is_some_and(|other| *this == *other))
        });
        methods.add_meta_method(
            LuaMetaMethod::Lt,
            |_, this, other: LuaUserDataRef<Version>| Ok(*this < *other),
        );
        methods.add_meta_method(
            LuaMetaMethod::Le,
            |_, this, other: LuaUserDataRef<Version>| Ok(*this <= *other),
        );
    }
}

impl Version {
    /// `semver.new([major[, minor[, patch[, pre[, build]]]]]) -> Version`
    fn lua_new(
        major: Option<u64>,
        minor: Option<u64>,
        patch: Option<u64>,
        pre: Option<String>,
        build: Option<String>,
    ) -> LuaResult<Self> {
        let mut version =
            SemverVersion::new(major.unwrap_or(0), minor.unwrap_or(0), patch.unwrap_or(0));
        version.pre = Prerelease::new(pre.as_deref().unwrap_or(""))
            .map_err(|error| LuaError::runtime(format!("invalid prerelease: {error}")))?;
        version.build = BuildMetadata::new(build.as_deref().unwrap_or(""))
            .map_err(|error| LuaError::runtime(format!("invalid build metadata: {error}")))?;
        Ok(Self(version))
    }

    /// `semver.parse(version) -> Version`
    fn lua_parse(version: &str) -> LuaResult<Self> {
        version
            .parse::<Self>()
            .map_err(|error| LuaError::runtime(format!("invalid semantic version: {error}")))
    }
}

type VersionNewArgs = (
    Option<u64>,
    Option<u64>,
    Option<u64>,
    Option<String>,
    Option<String>,
);

/// `semver.valid(version) -> boolean`
fn semver_valid(_: &Lua, version: LuaValue) -> LuaResult<bool> {
    let version = string_argument(&version, 1, "version", "valid")?;
    Ok(version.parse::<Version>().is_ok())
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::Version;

    #[test]
    fn implements_default_and_from_str() {
        assert_eq!(Version::default().to_string(), "0.0.0");

        let version: Version = "1.2.3-alpha.1+build.5".parse().unwrap();
        assert_eq!(version.to_string(), "1.2.3-alpha.1+build.5");
    }

    #[test]
    fn equality_ordering_and_hash_use_precedence() {
        let with_build_a: Version = "1.2.3+build.1".parse().unwrap();
        let with_build_b: Version = "1.2.3+build.2".parse().unwrap();
        let alpha: Version = "1.2.3-alpha".parse().unwrap();
        let release: Version = "1.2.3".parse().unwrap();

        assert_eq!(with_build_a, with_build_b);
        assert!(alpha < release);

        let mut versions = HashSet::new();
        versions.insert(with_build_a);
        assert!(versions.contains(&with_build_b));
    }
}
