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

local BasePlugin = require "kong.plugins.base_plugin"

-- Converter from SOAP-Rquest to REST-Rquest
local request_handler = require "kong.plugins.soap2rest.request_handler"

-- Converter from REST-Response to SOAP-Response
local response_handler = require "kong.plugins.soap2rest.response_handler"

-- Handler from WSDL file
local wsdl_handler = require "kong.plugins.soap2rest.wsdl_handler"

-- Handler from WSDL file
local openapi_handler = require "kong.plugins.soap2rest.openapi_handler"

--local inspect = require "inspect"

local soap2rest = BasePlugin:extend()

-- set the plugin priority, which determines plugin execution order (Default: 2001)
soap2rest.PRIORITY = 2001
soap2rest.VERSION = "1.0.2-1"

-- Processing of incoming requests
-- runs in the 'access_by_lua_block'
-- @param plugin_conf Plugin configuration
function soap2rest:access(plugin_conf)
    soap2rest.super.access(self)

    -- Logging of all HTTP headers
    local headers = kong.request.get_headers()
    for key, value in pairs(headers) do
        kong.log.debug("Header: " .. key .. "; Value: " .. value)
    end

    -- Automatic configuration if it has not yet been executed.
    if plugin_conf.operations == nil then
        -- Automatic configuration using the WSDL file
        local status, msg = pcall(wsdl_handler.parse, plugin_conf)
        if status then
            kong.log.debug("Successfully parsed WSDL file")
        else
            kong.log.err(msg)
        end

        -- Automatic configuration using the OpenAPI file
        local status, msg = pcall(openapi_handler.parse, plugin_conf)
        if status then
            kong.log.debug("Successfully parsed OpenAPI file")
        else
            kong.log.err(msg)
        end
    end

    -- Processing the SOAP request
    local status, requestAction = pcall(request_handler.convert, plugin_conf)
    if status then
        -- Storing the SAOP OperationId in the HTTP header of the REST request
        kong.service.request.set_header("X-SOAP-RequestAction", requestAction)
    else
        kong.log.err(requestAction)
    end
end

-- Processing the header of the outgoing response
-- runs in the 'header_filter_by_lua_block'
-- @param plugin_conf Plugin configuration
function soap2rest:header_filter(plugin_conf)
    soap2rest.super.header_filter(self)

    local RequestAction = kong.request.get_header("X-SOAP-RequestAction")

    -- Change response header to SOAP
    if RequestAction == nil or RequestAction == "WSDL_FILE" or plugin_conf.operations[RequestAction].rest.response.type:sub(-#"json") == "json" then
        kong.response.set_header("Content-Type","application/xml; charset=utf-8")
    else
        kong.response.set_header("Content-Type", plugin_conf.operations[RequestAction].rest.response.type)
    end
    kong.response.clear_header("Content-Length")

    kong.ctx.shared.restHttpStatus = kong.response.get_status()
    -- Change all client errors to status code 200, as SOAP errors are otherwise ignored by most frameworks.
    -- Unauthorized (401) and Forbidden (403) passed directly
    if kong.response.get_status() ~= 401 and kong.response.get_status() ~= 403 and tonumber(string.sub(kong.response.get_status(), 1,1)) == 4 then
        kong.response.set_status(200)
    end

    -- Change all server errors to error code 500
    if tonumber(string.sub(kong.response.get_status(), 1,1)) == 5 then
        kong.response.set_status(500)
    end

    -- sets response code for WSDL file
    if RequestAction == "WSDL_FILE" then
        if plugin_conf.wsdl_content ~= nil then
            kong.response.set_status(200)

        elseif kong.response.get_status() ~= 401 then
            kong.response.set_status(400)

        end
    end
end

-- Processing the body of the outgoing response
-- runs in the 'body_filter_by_lua_block'
-- @param plugin_conf Plugin configuration
function soap2rest:body_filter(plugin_conf)
    soap2rest.super.body_filter(self)

    -- Clear nginx buffers
    local ctx = ngx.ctx
    if ctx.buffers == nil then
        ctx.buffers = {}
        ctx.nbuffers = 0
    end

    -- Load response body
    local data = ngx.arg[1]
    local eof = ngx.arg[2]
    local next_idx = ctx.nbuffers + 1

    if not eof then
        if data then
            ctx.buffers[next_idx] = data
            ctx.nbuffers = next_idx
            ngx.arg[1] = nil
        end
        return
    elseif data then
        ctx.buffers[next_idx] = data
        ctx.nbuffers = next_idx
    end

    local RequestAction = kong.request.get_header("X-SOAP-RequestAction")

    -- Query whether the request is the WSDL
    if RequestAction == "WSDL_FILE" then
        ngx.arg[1] = plugin_conf.wsdl_content
    else
        local table_response = table.concat(ngx.ctx.buffers)
        local response_code = kong.ctx.shared.restHttpStatus

        -- Generating a SOAP response from the REST response
        local status, soap_response = pcall(response_handler.generateResponse, plugin_conf, table_response, response_code, RequestAction)
        if status then
            ngx.arg[1] = soap_response
        else
            kong.log.err(RequestAction.." ", soap_response)
        end
    end
end

-- Logging of each request via the plugin
-- runs in the 'log_by_lua_block'
-- @param plugin_conf Plugin configuration
function soap2rest:log(plugin_conf)
    soap2rest.super.log(self)

    local RequestAction = kong.request.get_header("X-SOAP-RequestAction")

    kong.log.debug("SOAP-Request action: '"..tostring(RequestAction).."'")
end

return soap2rest
