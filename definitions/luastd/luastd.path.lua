---@meta

--- A parsed UTF-8 path component.
---@class luastd.path.Component
---@field kind  string one of `"prefix"`, `"root"`, `"curdir"`, `"parentdir"`, or `"normal"`
---@field value string the component text; the root separator for `"root"`

--- A UTF-8 path.
---
--- Backed by `camino::Utf8PathBuf`. Paths are immutable: operations that would
--- change a path return a new one.
---
--- Only lexical path operations are exposed. Nothing in this module opens,
--- reads, or stats a file.
---
--- `==`, `<`, and `<=` compare components, matching `camino`.
---
--- `/` joins paths, Python `pathlib` style, so `path.new("a") / "b"` is
--- `path.new("a/b")`. The right operand may be a string or a `Path`; empty
--- operands are ignored.
---
--- Construct with `path.new`. There is no runtime `path.Path` class table.
---@class luastd.path.Path
---@operator eq(luastd.path.Path): boolean
---@operator lt(luastd.path.Path): boolean
---@operator le(luastd.path.Path): boolean
---@operator div(string | luastd.path.Path): luastd.path.Path
local Path = {}

--- Check whether the path is absolute.
---@return boolean
function Path:is_absolute() end

--- Check whether the path is relative.
---@return boolean
function Path:is_relative() end

--- Check whether the path has a root.
---@return boolean
function Path:has_root() end

--- Return the parent path, or `nil` at the root.
---@return luastd.path.Path | nil
function Path:parent() end

--- Return every ancestor, starting with this path and ending at the root or
--- the empty path.
---@return luastd.path.Path[]
function Path:ancestors() end

--- Return the final component, or `nil`.
---@return string | nil
function Path:file_name() end

--- Return the final component without its extension, or `nil`.
---@return string | nil
function Path:file_stem() end

--- Return the extension without the leading dot, or `nil`.
---
--- A trailing dot yields `""`; a leading dot names a hidden file and is not an
--- extension.
---@return string | nil
function Path:extension() end

--- Join every argument onto this path.
---
--- `nil` and empty arguments are ignored and an absolute argument replaces
--- this path, matching `Utf8PathBuf::push`. `path / other` is the same
--- operation.
---@param ... string | luastd.path.Path | nil
---@return luastd.path.Path
function Path:join(...) end

--- Replace the final component with `file_name`.
---
--- `file_name` may contain separators; they become path components.
---@param file_name string
---@return luastd.path.Path
function Path:with_file_name(file_name) end

--- Replace the extension with `extension`; an empty extension removes it.
---
--- Raises when `extension` contains a path separator.
---@param extension string
---@return luastd.path.Path
function Path:with_extension(extension) end

--- Append `extension` without replacing an existing one.
---
--- Raises when `extension` contains a path separator.
---@param extension string
---@return luastd.path.Path
function Path:with_added_extension(extension) end

--- Check whether this path starts with `base`, comparing whole components.
---@param base string
---@return boolean
function Path:starts_with(base) end

--- Check whether this path ends with `child`, comparing whole components.
---@param child string
---@return boolean
function Path:ends_with(child) end

--- Remove `prefix` from this path and return the remainder.
---
--- Raises when `prefix` is not a component-wise prefix.
---@param prefix string
---@return luastd.path.Path
function Path:strip_prefix(prefix) end

--- Return the parsed components, including root and `.`/`..` markers.
---@return luastd.path.Component[]
function Path:components() end

--- Path helpers provided by the `kbliblua` Rust host.
---
--- Wraps the lexical, UTF-8 path operations from the Rust `camino` crate.
--- Construct with `path.new`. `join` is the string-only module shortcut.
---@class luastd.path
local path = {}

--- Create a path by joining every argument from left to right.
---
--- `path.new()` is the empty path. Arguments may be strings or paths, `nil`
--- and empty arguments are ignored, and an absolute argument replaces
--- everything joined so far. Text is otherwise kept verbatim: joining does
--- not normalize `.`, `..`, or repeated separators, and never touches the
--- filesystem.
---@param ... string | luastd.path.Path | nil
---@return luastd.path.Path
function path.new(...) end

--- Join every argument from left to right and return the result as a string.
---
--- `nil` and empty arguments are ignored and an absolute argument replaces
--- everything joined so far, matching `Utf8PathBuf::push`. At least one
--- argument is required.
---@param ... string | luastd.path.Path | nil
---@return string
function path.join(...) end

return path
