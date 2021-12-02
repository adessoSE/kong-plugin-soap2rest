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

-- Convert encapsulated values
-- @param plugin_conf Plugin configuration
-- @param table Input value
-- @param level Encapsulation level
local function convertValues(plugin_conf, table, level)
    if table == nil then
        return
    end

    for key, value in pairs(table) do
        if type(value) == "table" then
            if next(value) == nil and level > 0 then
                -- empty tables except the root element must be removed
                -- otherwise they are rendered as an empty object ({})
                kong.log.debug("Removing "..key.." because it is an empty table")
                table[key] = nil
            else
                convertValues(plugin_conf, value, level + 1)
            end

        elseif tonumber(value) ~= nil and not string.match(value, "^0[^%.]%d*$") then
            -- Conversion of strings to numbers
            table[key] = tonumber(value)

        elseif utils.has_value(plugin_conf.soap_arrays, key) then
            -- Array conversion
            kong.log.debug("Forcing "..key.." to be an array")
            table[key] = { value }
            convertValues(plugin_conf, table[key], level + 1)
            setmetatable(table[key], cjson.array_mt)

        elseif string.match(value, "^{.*}$") then
            -- Conversion from JSON
            kong.log.debug("Converting "..key.." to be a JSON")
            table[key] = cjson.decode(value)

        end
    end
end

-- Conversion of XML namespaces to Lua tables
-- @param xml_request raw XML request
local function parseNamespaces(xml_request)
    local xmlNamespaces = {}
    for key, value in string.gmatch(xml_request, 'xmlns:([^=]*)="([^"]*)"') do
        kong.log.debug("Register Namespace: "..key.."="..value)
        xmlNamespaces[key] = "xmlns:"..key.."=\""..value.."\""
    end

    kong.ctx.shared.xmlNamespaces = xmlNamespaces
end

-- Query the abbreviation of a namespace
-- @param namespaceName Name of the namespace searched for
-- @return namespace Namespace abbreviation
local function getNamespace(namespaceName)
    return kong.ctx.shared.xmlNamespaces[namespaceName]
end

-- Query all namespace names
-- @param xml_data raw SOAP header as XML
-- @return alle Namespace Names in the SOAP header
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
end

-- Converting the SOAP request body into a Lua table
-- @param plugin_conf Plugin configuration
-- @return  1. SOAP header as Lua table
--          2. raw SOAP header as XML
--          3. SOAP body as Lua table
local function parseBody(plugin_conf)
    local xml_request, msg = kong.request.get_raw_body()

    -- Reading the body from a buffer if the body is too large
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

    -- Extract the SOAP header
    local soap_header_raw = string.gmatch(xml_request, '<[^:<>!]*:Header[%s>].*</[^:<>!]*:Header>')()

    -- Namespace short name removed from XML request
    xml_request = string.gsub( xml_request, "(<%/?)[^:<>!]*:", "%1" )
    kong.log.debug(xml_request)

    -- Parsing the XML request body into Lua table
    local request_handler = handler:new()
    local parser = xml2lua.parser(request_handler)
    parser:parse(xml_request)

    local soap_header = request_handler.root["Envelope"]["Header"]
    convertValues(plugin_conf, soap_header, 0)

    local soap_body = request_handler.root["Envelope"]["Body"]

    -- Remove attributes from the body, probably only namespaces
    if soap_body["_attr"] ~= nil then
        soap_body["_attr"] = nil
    end

    -- Convert encapsulated values
    convertValues(plugin_conf, soap_body, 0)

    return soap_header, soap_header_raw, soap_body
end

-- Convert SOAP header to HTTP header
-- @param soap_header SOAP header as Lua table
-- @param soap_header_raw raw SOAP header as XML
-- @param operation Configuration of the SOAP operations
local function convertHeader(soap_header, soap_header_raw, operation)
    -- Setting the HTTP Method
    kong.service.request.set_method(string.upper(operation.rest.action))

    -- Setting the request and response content types
    if (operation.rest.response and operation.rest.response.type) then
        kong.service.request.set_header("Accept", operation.rest.response.type)
    end
    if (operation.rest.request and operation.rest.request.type) then
        kong.service.request.set_header("Content-Type", operation.rest.request.type)
    end

    -- Converting the SOAP headers into HTTP headers
    if soap_header ~= nil then
        for key, value in pairs(soap_header) do
            if type(value) == "table" then
                local data = string.gmatch(soap_header_raw, "<[^:<>!]*:"..key.."[^>]*>(.*)</[^:<>!]*:"..key..">")()

                -- save security header to ctx map because base64 encoding and kong header breaks the content
                if string.lower(key) == "security" then
                    -- Retrieve all namespace names
                    local namespaces = referencedNamespacesAsString(data)
                    kong.log.debug("Namespaces für Header: "..namespaces)

                    -- register at the first xml element
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
end

-- Conversion from SOAP request to REST GET
-- @param operation Konfiguration der SOAP Operationen
-- @param bodyValue SOAP body as Lua table
function convertGET(operation, bodyValue)
    local RequestParams = "?"

    local RequestPath = operation.rest.path

    -- Identifying URL parameters
    for key, value in pairs(bodyValue) do
        -- Escaping all GET parameters
        value = ngx.escape_uri(value, 2)

        -- Escaping all '%', as string.gsub sont does not work
        value = value:gsub("%%", "%%%%")

        local count
        RequestPath, count = string.gsub(RequestPath, "{"..key.."}", value)
        if count == 0 and type(value) ~= "table" then
            -- Replace the double escaped '%'
            value = value:gsub("%%%%", "%%")
            RequestParams = RequestParams..key.."="..value.."&"
        end
    end
    RequestParams = string.sub(RequestParams, 1, -2)

    -- Remove unused path parameters
    RequestPath = string.gsub(RequestPath, '(%/{%w*})', '')

    -- Set the request path
    local combined_request_path = RequestPath..RequestParams
    kong.log.debug("Combined Request Path: "..combined_request_path)
    kong.service.request.set_path(combined_request_path)

    -- Change the request header to REST
    kong.service.request.set_raw_body("")
    kong.service.request.clear_header("Content-Type")
    kong.service.request.clear_header("Content-Length")
end

-- Converting a Hex String to a String
-- @param str Hex string
-- @return String
local function parseHex(str)
    return (
        str:gsub('..', function (cc)
            return string.char(tonumber(cc, 16))
        end
        )
    )
end

-- Generation of a random boundary
-- @param length Length of the boundary
-- @return random boundary
local function randomBoundary(length)
    local characterSet = "abcdefghijklmnopqrstuvwxyz0123456789"

    local output = ""
    for i = 1, length do
        local rand = math.random(#characterSet)
        output = output .. string.sub(characterSet, rand, rand)
    end

    return output
end

local function guessFileName(content_type)
    -- default is CSV because TXT and CSV cannot be distinguished
    local file_name = "upload.csv"

    if content_type ~= nil and string.find(content_type, "zip") ~= nil then
        file_name = "upload.zip"
    end

    return file_name
end

-- Conversion from SOAP request to REST POST
-- @param operation Configuration of the SOAP operations
-- @param bodyValue SOAP body as Lua table
local function convertPOST(operation, bodyValue)
    local RequestPath = operation.rest.path

    local body = {}

    if (not operation.rest.request or not operation.rest.request.type or string.find(operation.rest.request.type, "multipart/") == nil) then
        -- Conversion of a SOAP body into JSON
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
        -- Converting a file into a Multipart Body
        kong.log.debug("Sending Multipart")
        -- Setting the Boundary header
        local multipartContentType = "multipart/form-data; boundary=----------"..randomBoundary(10)
        kong.service.request.set_header("Content-Type", multipartContentType)

        -- Creating a multipart
        local multipart_data = Multipart(nil, multipartContentType)

        if bodyValue.datei ~= nil then
            local hex = bodyValue.datei:gsub(" ", "")
            local data = parseHex(hex)
            local content_type = puremagic.via_content(data)
            local file_name = guessFileName(content_type)

            kong.log.debug("Datei Content-Type: "..content_type)
            multipart_data:set_simple("datei", data, file_name, content_type)

        end

        if bodyValue.metadaten ~= nil then
            local metadata = cjson.encode(bodyValue.metadaten)
            multipart_data:set_simple("metadaten", metadata, "meta.tmp", operation.rest.request.encoding.meta)
        end

        body = multipart_data:tostring()
    end

    -- Remove unused path parameters
    RequestPath = string.gsub(RequestPath, '(%/{%w*})', '')
    kong.log.debug("Routing to: "..RequestPath)

    -- Change request path
    kong.service.request.set_path(RequestPath)
    if (type(body) == "table") then
        body = cjson.encode(body)
    end

    kong.log.debug("Upstream Body: "..body)

    kong.service.request.set_raw_body(body)
end

-- Convert a SOAP request to a REST request
-- @param plugin_conf Plugin configuration
-- @return SOAP OperationId
function _M.convert(plugin_conf)
    if string.upper(kong.request.get_raw_query()) == "WSDL" then
        return "WSDL_FILE"
    end

    local status, soap_header, soap_header_raw, soap_body = pcall(parseBody, plugin_conf)
    if not status then
        kong.log.err("Unable to parse soap request body\n\t", soap_header)
        return nil
    end

    -- SOAP request body analyse
    local RequestAction, bodyValue = next(soap_body)
    kong.log.debug("Parsed Operation: "..RequestAction)

    RequestAction = string.gsub( RequestAction, "_InputMessage", "" )

    local operation = plugin_conf.operations[RequestAction]
    kong.log.debug("SOAP Operation: "..RequestAction.." REST Operation: "..operation.rest.path)

    -- Convert SOAP header
    convertHeader(soap_header, soap_header_raw, operation)

    -- Convert SOAP Body
    local action = {
        ["get"] = function() convertGET(operation, bodyValue) end,
        ["post"] = function() convertPOST(operation, bodyValue) end,
    }

    action[operation.rest.action]()

    return RequestAction
end

return _M