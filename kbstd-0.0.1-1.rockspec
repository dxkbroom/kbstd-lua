rockspec_format = "3.1"
package = "kbstd"
version = "0.0.1-1"

dependencies = {
	"lua>=5.1",
}

build_dependencies = {
	"luarocks-build-rust-mlua>=0.2.6",
}

source = {
	url = "https://github.com/dxkbroom/kbstd-lua",
}

build = {
	type = "rust-mlua",
	modules = {
		kbstd = "kbstd",
	},
}
