rockspec_format = "3.0"

package = "multimodal"
version = "dev-1"

source = {
    url = "git+https://github.com/catwell/multimodal.git",
}

description = {
    summary = "Watch logs of all Modal apps in a single environment",
    license = "MIT",
}

dependencies = {
    "lua >= 5.4",
    "argparse",
    "lua-cjson",
    "terminal",
}

build = {
    type = "builtin",
    modules = {},
    install = {
        bin = {
            multimodal = "multimodal.lua",
        },
    },
}
