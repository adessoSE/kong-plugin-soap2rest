-- Configuration file for LuaCheck
-- see: https://luacheck.readthedocs.io/en/stable/
--
-- To run do: `luacheck .` from the repo

std             = "ngx_lua"
unused_args     = false
redefined       = false
max_line_length = false


globals = {
    "_KONG",
    "kong",
    "ngx.IS_CLI",
}


ignore = {
    "6.", -- ignore whitespace warnings
}


files["spec/soap2rest/**/*.lua"] = {
    std = "ngx_lua+busted",
}
