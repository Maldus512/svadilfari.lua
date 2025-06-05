package = "svadilfari"
version = "0.1-1"
source = {
    url = "git://github.com/Maldus512/svadilfari"
}
description = {
    summary = "A simple and effective build configuration tool",
    detailed = [[]],
    license = "MIT"
}
dependencies = {
    "lua ~> 5.4"
}
build = {
    type = "builtin",
    modules = {
        ["svadilfari.utils"] = "src/utils.c",
        ["svadilfari"] = "src/svadilfari.lua",
    },
    install = {
        bin = { svad = "src/svad.lua" },
    },
}
