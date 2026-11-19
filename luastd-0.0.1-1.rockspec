rockspec_format = "3.1"
package = "luastd"
version = "0.0.1-1"

dependencies = {
	"lua>=5.1",
}

build_dependencies = {
	"luarocks-build-rust-mlua>=0.2.6",
}

source = {
	url = "https://github.com/dxkbroom/luastd",
}

build = {
	type = "rust-mlua",
	cargo_extra_args = { "-p", "luastd_lua" },
	modules = {
		luastd = "luastd_lua",
	},
}
