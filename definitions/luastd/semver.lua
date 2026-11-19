---@meta luastd.semver

--- A semantic version.
---
--- Backed by `semver::Version`. Build metadata is ignored by `==` and by the
--- ordering operators, as required by the Semantic Versioning spec.
---
--- Construct with `semver.new` / `semver.parse` / `semver.default`. There is
--- no runtime `semver.Version` class table.
---@class luastd.semver.Version
---@field major integer
---@field minor integer
---@field patch integer
---@field pre   string  dot-separated prerelease identifiers, or `""`
---@field build string  dot-separated build identifiers, or `""`
---@operator eq(luastd.semver.Version): boolean
---@operator lt(luastd.semver.Version): boolean
---@operator le(luastd.semver.Version): boolean
local Version = {}

--- Compare this version with `other`.
---@param other luastd.semver.Version
---@return integer comparison `-1`, `0`, or `1`
function Version:cmp(other) end

--- Check whether this version satisfies `requirement`.
---
--- Raises when `requirement` is invalid.
---@param requirement string
---@return boolean
function Version:satisfies(requirement) end

--- Semantic version helpers.
---
--- Wraps the Rust `semver` crate. Construct with `semver.new` /
--- `semver.parse` / `semver.default`.
---@class luastd.semver
local semver = {}

--- Create a version.
---
--- Omitted components default to zero, so `semver.new()` is `0.0.0`.
---@param major? integer
---@param minor? integer
---@param patch? integer
---@param pre?   string
---@param build? string
---@return luastd.semver.Version
function semver.new(major, minor, patch, pre, build) end

--- Parse a semantic version string.
---
--- Raises when `version` is invalid. Use `semver.valid` to check a string
--- without raising.
---@param version string
---@return luastd.semver.Version
function semver.parse(version) end

--- Create the default version, `0.0.0`.
---@return luastd.semver.Version
function semver.default() end

--- Check whether `version` is a valid semantic version.
---
--- Never raises; returns `false` for invalid input.
---@param version string
---@return boolean
function semver.valid(version) end

return semver
