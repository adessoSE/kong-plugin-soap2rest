------------------------------------------------------------------------------
-- kong-plugin-soap2rest 1.0.2-1
------------------------------------------------------------------------------
-- Copyright 2021 adesso SE
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
------------------------------------------------------------------------------
-- Author: Daniel Kraft <daniel.kraft@adesso.de>
------------------------------------------------------------------------------

local cjson = require "cjson.safe"
local xml2lua = require "xml2lua"
local handler = require "xmlhandler.tree"
local base64 = require "base64"
local Multipart = require "multipart"

local puremagic = require "kong.plugins.soap2rest.puremagic"

--local inspect = require "inspect"

local _M = {}

---[[ reads the OpenAPI file
local function read_file(path)
    local file = io.open(path, "r")
    local content = file:read("*a")
    file:close()
    kong.log.debug(os.remove(path))
    return content
end --]]

---[[ convert number values to number
local function convertToNumber(table)
    for key, value in pairs(table) do
        if type(value) == "table" then
            convertToNumber(value)
        elseif tonumber(value) ~= nil and not string.match(value, "^0[^%.]%d*$") then
            table[key] = tonumber(value)
        end
    end
end --]]

---[[ parse SOAP request body to Lua table
local function parseBody()
    local xml_request, msg = kong.request.get_raw_body()

    if xml_request == nil then
        kong.log.debug(msg)
        local temp_file = ngx.req.get_body_file()

        local status
        status, xml_request = pcall(read_file, temp_file)
        if not status then
            error("Unable to read buffered file '"..temp_file.."' \n\t"..xml_request)
        end
    end

    local soap_header_raw = string.gmatch(xml_request, '<[^:<>!]*:Header[%s>].*</[^:<>!]*:Header>')()

    -- Removed namespace shortname from XML request
    xml_request = string.gsub( xml_request, "(<%/?)[^:<>!]*:", "%1" )
    kong.log.debug(xml_request)

    -- Parse XML request body to Lua table
    local request_handler = handler:new()
    local parser = xml2lua.parser(request_handler)
    parser:parse(xml_request)

    local soap_header = request_handler.root["Envelope"]["Header"]
    convertToNumber(soap_header)

    local soap_body = request_handler.root["Envelope"]["Body"]
    convertToNumber(soap_body)

    return soap_header, soap_header_raw, soap_body
end --]]

---[[ convert SOAP header to REST header
local function convertHeader(soap_header, soap_header_raw, operation)
    kong.service.request.set_method(string.upper(operation.rest.action))
    if (operation.rest.response and operation.rest.response.type) then
        kong.service.request.set_header("Accept", operation.rest.response.type)
    end
    if (operation.rest.request and operation.rest.request.type) then
        kong.service.request.set_header("Content-Type", operation.rest.request.type)
    end

    if soap_header ~= nil then
        for key, value in pairs(soap_header) do
            if type(value) == "table" then
                local data = string.gmatch(soap_header_raw, "<[^:<>!]*:"..key.."[%s>]+.*</[^:<>!]*:"..key..">")()
                local encoded_data = base64.encode(data)
                kong.service.request.set_header(key, encoded_data)
            else
                kong.service.request.set_header(key, value)
            end
        end
    end
end --]]

---[[ convert SOAP request to REST GET
local function convertGET(operation, bodyValue)
    local RequestParams = "?"

    local RequestPath = operation.rest.path

    -- Analyse request body
    for key, value in pairs(bodyValue) do
        local count
        RequestPath, count = string.gsub(RequestPath, "{"..key.."}", value)
        if count == 0 then RequestParams = RequestParams..key.."="..value.."&" end
    end
    RequestParams = string.sub(RequestParams, 1, -2)

    -- Remove unused path params
    RequestPath = string.gsub(RequestPath, '(%/{%w*})', '')

    -- Change request path
    kong.service.request.set_path(RequestPath..RequestParams)

    -- Change request header to REST
    kong.service.request.set_raw_body("")
    kong.service.request.clear_header("Content-Type")
    kong.service.request.clear_header("Content-Length")
end --]]

---[[ convert hex string to string
local function parseHex(str)
    return (str:gsub('..', function (cc) return string.char(tonumber(cc, 16)) end))
end --]]

---[[ convert SOAP request to REST POST
local function convertPOST(operation, bodyValue)
    local RequestPath = operation.rest.path

    -- Analyse request body
    local body = {}

    if (not operation.rest.request or not operation.rest.request.type or operation.rest.request.type ~= "multipart/mixed") then
        for key, value in pairs(bodyValue) do
            local count
            RequestPath, count = string.gsub(RequestPath, "{"..key.."}", value)
            if count == 0 then
                if key == "body" then
                    for body_key, body_value in pairs(value) do
                        body[body_key] = body_value
                    end
                else
                    body[key] = value
                end
            end
        end
    else
        local multipart_data = Multipart({}, "multipart/mixed")

        if bodyValue.datei ~= nil then
            local hex = bodyValue.datei:gsub(" ", "")
            local content_type = puremagic.via_content(parseHex(hex))
            multipart_data:set_simple("datei", bodyValue.datei, "filename.temp", content_type)
        end

        if bodyValue.metadaten ~= nil then
            local metadata = cjson.encode(bodyValue.metadaten)
            multipart_data:set_simple("metadaten", metadata, "filename.temp", operation.rest.request.encoding.meta)
        end

        body = multipart_data:tostring()
        body = body:gsub("; filename=\"filename.temp\"", "")
    end

    -- Remove unused path params
    RequestPath = string.gsub(RequestPath, '(%/{%w*})', '')
    kong.log.debug("Routing to: "..RequestPath)

    -- Change request path
    kong.service.request.set_path(RequestPath)
    if (type(body) == "table") then
        body = cjson.encode(body)
        kong.log.debug("Upstream Body: "..body)
    end

    kong.service.request.set_raw_body(body)
end --]]

---[[ convert SOAP request to REST call
function _M.convert(plugin_conf)
    if string.upper(kong.request.get_raw_query()) == "WSDL" then
        return "WSDL_FILE"
    end

    local status, soap_header, soap_header_raw, soap_body = pcall(parseBody)
    if not status then
        kong.log.err("Unable to parse soap request body\n\t", soap_header)
        return nil
    end

    -- Analyse request body
    local RequestAction, bodyValue = next(soap_body)
    kong.log.debug("Parsed Operation: "..RequestAction)

    RequestAction = string.gsub( RequestAction, "_InputMessage", "" )

    local operation = plugin_conf.operations[RequestAction]
    kong.log.debug("SOAP Operation: "..RequestAction.." REST Operation: "..operation.rest.path)

    -- Convert soap header to rest header
    convertHeader(soap_header, soap_header_raw, operation)

    -- Convert soap body to rest body
    local action = {
        ["get"] = function() convertGET(operation, bodyValue) end,
        ["post"] = function() convertPOST(operation, bodyValue) end,
    }

    action[operation.rest.action]()

    return RequestAction
end --]]

return _M