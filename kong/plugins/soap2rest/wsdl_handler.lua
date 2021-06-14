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

local xml2lua = require "xml2lua"
local handler = require "xmlhandler.tree"

local utils = require "kong.plugins.soap2rest.utils"

--local inspect = require "inspect"

local _M = {}

-- Identify namespaces from the WSDL schema
-- @param raw_schema Schema Excerpt from the WSDL
-- @return  1: Lua table with namespaces and the appropriate abbreviations
--          2: Abbreviations of the target namespace
local function parse_namespaces(raw_schema)

    local namespaces = {}
    local targetNamespace = ""

    -- Identify WSDL namespaces and the appropriate abbreviations
    for key, value in pairs(raw_schema._attr) do
        if string.match(key, '^(xmlns):') == 'xmlns' then
            namespaces[string.match(key, ':(.*)$')] = value
        elseif key == 'targetNamespace' then
            targetNamespace = value
        end
    end

    -- Identifying the abbreviations of the target namespace
    for key, value in pairs(namespaces) do
        if value == targetNamespace then
            targetNamespace = key
            break
        end
    end

    return namespaces, targetNamespace
end

-- Identifying the types of SOAP requests and responses
-- @param raw_schema Schema Excerpt from the WSDL
-- @return Mapping of InputMessage or OutputMessage and their types
local function parse_schema(raw_schema)
    -- Identify the types
    local types = {}
    for key, value in pairs(raw_schema['xs:complexType']) do
        if value._attr.name:sub(-#'_OutputMessage') == '_OutputMessage' then
            if value['xs:sequence'] ~= nil and value['xs:sequence']['xs:element'] ~= nil then
                -- xs typen are basic values
                if value['xs:sequence']['xs:element']._attr.type ~= nil and value['xs:sequence']['xs:element']._attr.type:find('^xs:') == nil then
                    types[value._attr.name] = value['xs:sequence']['xs:element']._attr.type:gsub("schemas:", "")
                else
                    types[value._attr.name] = value['xs:sequence']['xs:element']._attr.name
                end
            elseif value['xs:element'] ~= nil then
                if value['xs:element']._attr.type ~= nil then
                    types[value._attr.name] = value['xs:element']._attr.type:gsub("schemas:", "")
                else
                    types[value._attr.name] = value['xs:element']._attr.name
                end
            end
        end
    end

    -- Assigning the types to InputMessage and OutputMessage respectively.
    local schema = {}
    for key, value in pairs(raw_schema['xs:element']) do
        if value._attr.name:sub(-#'_OutputMessage') == '_OutputMessage'  then
            schema[value._attr.name] = types[value._attr.name]
        elseif value._attr.name:sub(-#'_InputMessage') ~= '_InputMessage' then
            schema[value._attr.name] = (value._attr.type ~= nil and value._attr.type:gsub("schemas:", "") or value._attr.name)
        end
    end

    return schema
end

-- Identify the SOAP operations
-- @param raw_operations Operation Excerpt from the WSDL
-- @param schema Mapping of InputMessage or OutputMessage and their types
-- @return Mapping of OperationID and return types and possible faults
local function parse_operations(raw_operations, schema)
    local operations = {}
    for key, value in pairs(raw_operations) do
        local response, fault400, fault500 = nil, nil, nil

        if value.output ~= nil then
            response = schema[value.output._attr.message:gsub("wsdl:", "")]
        end

        -- Identifying the faults
        if value.fault ~= nil then
            -- Special case where only one fault is indicated
            if table.getn(value.fault) < 2 then
                -- Identifying the Client Faults
                if string.match(value.fault._attr.name, '_(4)[0-9][0-9]$') == '4' then
                    fault400 = {
                        name = value.fault._attr.name,
                        type = schema[value.fault._attr.name]
                    }

                -- Identify the server faults
                elseif string.match(value.fault._attr.name, '_(5)[0-9][0-9]$') == '5' then
                    fault500 = {
                        name = value.fault._attr.name,
                        type = schema[value.fault._attr.name]
                    }
                end
            else
                for key, value in pairs(value.fault) do
                    -- Identifying the Client Faults
                    if string.match(value._attr.name, '_(4)[0-9][0-9]$') == '4' then
                        if fault400 == nil or string.match(value._attr.name, '_(400)$') == '400'then
                            fault400 = {
                                name = value._attr.name,
                                type = schema[value._attr.name]
                            }
                        end

                    -- Identify the server faults
                    elseif string.match(value._attr.name, '_(5)[0-9][0-9]$') == '5' then
                        if fault500 == nil or string.match(value._attr.name, '_(500)$') == '500'then
                            fault500 = {
                                name = value._attr.name,
                                type = schema[value._attr.name]
                            }
                        end
                    end
                end
            end
        end

        -- Composing the SAOP return types
        operations[value._attr.name] = {
            soap = {
                response=response,
                fault400=fault400,
                fault500=fault500
            }
        }
    end

    return operations
end

-- Analysing ordered response models and soap arrays
-- @param complex_types Excerpt of all ComplexTypes from the WSDL
-- return   1. Configuration of the return types
--          2. Collection of the names of all SOAP arrays
local function parse_complexTypes(complex_types)
    local models = {}
    local soap_arrays = {}

    for _, type in pairs(complex_types) do
        if type['xs:sequence'] ~= nil then
            local attr = {}
            -- Checking whether it is an array of attributes
            if table.getn(type['xs:sequence']['xs:element']) > 1 then
                for _, value in pairs(type['xs:sequence']['xs:element']) do
                    -- Collecting attributes and their type
                    table.insert(attr, {
                        name = value._attr.name,
                        type = (value._attr.type:sub(1, #"schemas:") == "schemas:" and string.gsub(value._attr.type, "([^:]*:)", "" ) or nil)
                    })

                    -- Collecting the names of SOAP arrays
                    if value._attr.maxOccurs ~= nil and value._attr.maxOccurs == "unbounded" and not utils.has_value(soap_arrays, value._attr.name) then
                        table.insert(soap_arrays, value._attr.name)
                    end
                end
            else
                local value = type['xs:sequence']['xs:element']
                -- Collecting attributes and their type
                table.insert(attr, {
                    name = value._attr.name,
                    type = (value._attr.type:sub(1, #"schemas:") == "schemas:" and string.gsub(value._attr.type, "([^:]*:)", "" ) or nil)
                })

                -- Collecting the names of SOAP arrays
                if value._attr.maxOccurs ~= nil and value._attr.maxOccurs == "unbounded" and not utils.has_value(soap_arrays, value._attr.name) then
                    table.insert(soap_arrays, value._attr.name)
                end
            end
            models[type._attr.name] = attr
        end
    end
    return models, soap_arrays
end

-- Analysing the WSDL file and initiating the cached plug-in configuration
-- @param plugin_conf Plugin configuration
function _M.parse(plugin_conf)
    -- Reading the WSDL file
    local status, wsdl_content = pcall(utils.read_file, plugin_conf.wsdl_path)

    if not status then
        kong.log.err("Unable to read WSDL file '"..plugin_conf.wsdl_path.."' \n\t", wsdl_content)
        return
    end

    -- Convert WSDL file into a Lua table
    local wsdl_handler = handler:new()
    local parser = xml2lua.parser(wsdl_handler)
    parser:parse(wsdl_content)

    plugin_conf.wsdl_content = wsdl_content

    -- Identify namespaces from the WSDL schema
    local status, namespaces, targetNamespace = pcall(parse_namespaces, wsdl_handler.root.definitions.types['xs:schema'])
    if not status then
        kong.log.err("Unable to parse WSDL namespaces\n\t", namespaces)
        return
    end

    plugin_conf.namespaces = namespaces
    plugin_conf.targetNamespace = targetNamespace

    -- Identifying the types of SOAP requests and responses
    local status, schema = pcall(parse_schema, wsdl_handler.root.definitions.types['xs:schema'])
    if not status then
        kong.log.err("Unable to parse WSDL schema\n\t", schema)
        return
    end

    -- Identify the SOAP operations
    local status, operations = pcall(parse_operations, wsdl_handler.root.definitions.portType.operation, schema)
    if not status then
        kong.log.err("Unable to parse WSDL operations\n\t", operations)
        return
    end

    plugin_conf.operations = operations

    -- Analysing ordered response models and soap arrays
    local status, models, soap_arrays = pcall(parse_complexTypes, wsdl_handler.root.definitions.types['xs:schema']['xs:complexType'])
    if not status then
        kong.log.err("Unable to parse WSDL complexType\n\t", models)
        return
    end

    plugin_conf.models = models
    plugin_conf.soap_arrays = soap_arrays
end

return _M