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

local utils = require "kong.plugins.soap2rest.utils"
local puremagic = require "kong.plugins.soap2rest.puremagic"

--local inspect = require "inspect"

local _M = {}

---[[ convert values
local function convertValues(plugin_conf, table, ebene)
    if table == nil then
        return
    end

    for key, value in pairs(table) do
        if type(value) == "table" then
            if next(value) == nil and ebene > 0 then
                -- leere tables außer das root element müssen entfernt werden
                -- sonst werden sie als leeres objekt ({}) gerendert
                kong.log.debug("Removing "..key.." because it is an empty table")
                table[key] = nil
            else
                convertValues(plugin_conf, value, ebene + 1)
            end

        elseif tonumber(value) ~= nil and not string.match(value, "^0[^%.]%d*$") then
            -- convert numbers
            table[key] = tonumber(value)

        elseif utils.has_value(plugin_conf.soap_arrays, key) then
            -- fix arrays
            kong.log.debug("Forcing "..key.." to be an array")
            table[key] = { value }
            convertValues(plugin_conf, table[key], ebene + 1)
            setmetatable(table[key], cjson.array_mt)

        elseif string.match(value, "^{.*}$") then
            -- convert JSON
            kong.log.debug("Converting "..key.." to be a JSON")
            table[key] = cjson.decode(value)

        end
    end
end --]]

---[[ parse XML namespaces to Lua table
local function parseNamespaces(xml_request)
    local xmlNamespaces = {}
    for key, value in string.gmatch(xml_request, 'xmlns:([^=]*)="([^"]*)"') do
        kong.log.debug("Register Namespace: "..key.."="..value)
        xmlNamespaces[key] = "xmlns:"..key.."=\""..value.."\""
    end

    kong.ctx.shared.xmlNamespaces = xmlNamespaces
end --]]

---[[ parse XML namespaces to Lua table
local function getNamespace(namespaceName)
    return kong.ctx.shared.xmlNamespaces[namespaceName]
end --]]

---[[ get the referenced namespaces
local function referencedNamespacesAsString(xml_data)
    local namespaces = {}
    for namespaceName in string.gmatch(xml_data, '<([^/:]*):') do
        namespaces[namespaceName] = getNamespace(namespaceName)
    end

    local namespaceString = ""
    for key, namespace in pairs(namespaces) do
        if namespace ~= nil then
            namespaceString = namespaceString.." "..namespace
        else
            kong.log.debug("Namespace "..key.." not found")
        end
    end

    return namespaceString
end --]]

---[[ parse SOAP request body to Lua table
local function parseBody(plugin_conf)
    local xml_request, msg = kong.request.get_raw_body()

    if xml_request == nil then
        kong.log.debug(msg)
        local temp_file = ngx.req.get_body_file()

        local status
        status, xml_request = pcall(utils.read_file, temp_file)
        kong.log.debug(os.remove(temp_file))
        if not status then
            error("Unable to read buffered file '"..temp_file.."' \n\t"..xml_request)
        end
    end

    parseNamespaces(xml_request)
    local soap_header_raw = string.gmatch(xml_request, '<[^:<>!]*:Header[%s>].*</[^:<>!]*:Header>')()

    -- Removed namespace shortname from XML request
    xml_request = string.gsub( xml_request, "(<%/?)[^:<>!]*:", "%1" )
    kong.log.debug(xml_request)

    -- Parse XML request body to Lua table
    local request_handler = handler:new()
    local parser = xml2lua.parser(request_handler)
    parser:parse(xml_request)

    local soap_header = request_handler.root["Envelope"]["Header"]
    convertValues(plugin_conf, soap_header, 0)

    local soap_body = request_handler.root["Envelope"]["Body"]

    -- remove attributes from body, propably only namespaces
    if soap_body["_attr"] ~= nil then
        soap_body["_attr"] = nil
    end

    convertValues(plugin_conf, soap_body, 0)

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
                local data = string.gmatch(soap_header_raw, "<[^:<>!]*:"..key.."[^>]*>(.*)</[^:<>!]*:"..key..">")()

                -- save security header to ctx map because base64 encoding and kong header breaks the content
                if string.lower(key) == "security" then
                    -- alle namespace namen abrufen 
                    local namespaces = referencedNamespacesAsString(data)
                    kong.log.debug("Namespaces für Header: "..namespaces)

                    -- am ersten xml element registrieren
                    data = string.gsub(data, "^[ \r\n]*<([^:<>!]*:[^%s>]*)[^>]*>", "<%1 "..namespaces..">")

                    kong.ctx.shared.soapSecurityHeader = data
                else
                    local encoded_data = base64.encode(data)
                    kong.service.request.set_header(key, encoded_data)
                end
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
        if count == 0 and type(value) ~= "table" then 
            RequestParams = RequestParams..key.."="..ngx.escape_uri(value).."&"
        end
    end
    RequestParams = string.sub(RequestParams, 1, -2)

    -- Remove unused path params
    RequestPath = string.gsub(RequestPath, '(%/{%w*})', '')

    -- Change request path
    local combined_request_path = RequestPath..RequestParams
    kong.log.debug("Combined Request Path: "..combined_request_path)
    kong.service.request.set_path(combined_request_path)

    -- Change request header to REST
    kong.service.request.set_raw_body("")
    kong.service.request.clear_header("Content-Type")
    kong.service.request.clear_header("Content-Length")
end --]]

---[[ convert hex string to string
local function parseHex(str)
    return (
        str:gsub('..', function (cc)
            return string.char(tonumber(cc, 16))
        end
        )
    )
end --]]

---[[ generate random boundary
local function randomBoundary(length)
    local characterSet = "abcdefghijklmnopqrstuvwxyz0123456789"

    local output = ""
    for i = 1, length do
        local rand = math.random(#characterSet)
        output = output .. string.sub(characterSet, rand, rand)
    end

    return output
end --]]

---[[ convert SOAP request to REST POST
local function convertPOST(operation, bodyValue)
    local RequestPath = operation.rest.path

    -- Analyse request body
    local body = {}

    if (not operation.rest.request or not operation.rest.request.type or string.find(operation.rest.request.type, "multipart/") == nil) then
        if operation.rest.request ~= nil and operation.rest.request.type ~= nil then
            kong.log.debug("REST Request Type: "..operation.rest.request.type)
        else
            kong.log.debug("REST Request Type: undefined")
        end

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
        kong.log.debug("Sending Multipart")
        -- set boundary header
        local multipartContentType = "multipart/form-data; boundary=----------"..randomBoundary(10)
        kong.service.request.set_header("Content-Type", multipartContentType)

        -- multipart uses boundary header
        local multipart_data = Multipart(nil, multipartContentType)

        if bodyValue.datei ~= nil then
            local hex = bodyValue.datei:gsub(" ", "")
            local data = parseHex(hex)
            local content_type = puremagic.via_content(data)

            kong.log.debug("Datei Content-Type: "..content_type)
            multipart_data:set_simple("datei", data, "upload.tmp", content_type)

        end

        if bodyValue.metadaten ~= nil then
            local metadata = cjson.encode(bodyValue.metadaten)
            multipart_data:set_simple("metadaten", metadata, "meta.tmp", operation.rest.request.encoding.meta)
        end

        body = multipart_data:tostring()
    end

    -- Remove unused path params
    RequestPath = string.gsub(RequestPath, '(%/{%w*})', '')
    kong.log.debug("Routing to: "..RequestPath)

    -- Change request path
    kong.service.request.set_path(RequestPath)
    if (type(body) == "table") then
        body = cjson.encode(body)
    end

    kong.log.debug("Upstream Body: "..body)

    kong.service.request.set_raw_body(body)
end --]]

---[[ convert SOAP request to REST call
function _M.convert(plugin_conf)
    if string.upper(kong.request.get_raw_query()) == "WSDL" then
        return "WSDL_FILE"
    end

    local status, soap_header, soap_header_raw, soap_body = pcall(parseBody, plugin_conf)
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