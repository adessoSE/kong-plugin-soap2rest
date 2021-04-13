package = "kong-plugin-soap2rest"

version = "1.0.2-1"

local pluginName = package:match("^kong%-plugin%-(.+)$")  -- "soap2rest"

supported_platforms = {"linux", "macosx"}
source = {
  url = "https://github.com/adessoAG/kong-plugin-soap2rest",
  tag = "1.0.2-1"
}

description = {
  summary = "A plugin for the Kong Microservice API Gateway to redirect a SOAP request to a REST API and convert the JSON Response to SOAP response.",
  homepage = "https://www.adesso.de/de/",
  license = "Apache 2.0"
}

dependencies = {
  "lua ~> 5.1",
  "lua-cjson >= 2.1.0.6-1",
  "xml2lua >= 1.4-3",
  "lyaml >= 6.2.7-1",
  "multipart >= 0.5.9-1",
  "base64 >= 1.5-3",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins."..pluginName..".handler"] = "kong/plugins/"..pluginName.."/handler.lua",
    ["kong.plugins."..pluginName..".schema"] = "kong/plugins/"..pluginName.."/schema.lua",
    ["kong.plugins."..pluginName..".request_handler"] = "kong/plugins/"..pluginName.."/request_handler.lua",
    ["kong.plugins."..pluginName..".response_handler"] = "kong/plugins/"..pluginName.."/response_handler.lua",
    ["kong.plugins."..pluginName..".wsdl_handler"] = "kong/plugins/"..pluginName.."/wsdl_handler.lua",
    ["kong.plugins."..pluginName..".openapi_handler"] = "kong/plugins/"..pluginName.."/openapi_handler.lua",
    ["kong.plugins."..pluginName..".puremagic"] = "kong/plugins/"..pluginName.."/puremagic.lua",
  }
}
