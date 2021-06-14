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

--local inspect = require "inspect"

local _M = {}

-- Convert value to xml-compatible value. Bad characters are escaped
-- @param simpleValue Input value
-- @return Input value as XML entry
local function toXmlValue(simpleValue)
    local xmlValue
    if simpleValue ~= nil and simpleValue ~= cjson.null then
        xmlValue = tostring(simpleValue)
    else
        xmlValue = ""
    end

    -- escape special signs
    if string.match(xmlValue, "[\"'<>&]") then
        xmlValue = "<![CDATA["..xmlValue.."]]>"
    end

    return xmlValue
end

-- Create the sorted XML object
-- @param plugin_conf Plugin configuration
-- @param objectname Name of the object entry
-- @param objecttype Type of object entry
-- @param object object entry
-- @param tab Tabulator for structuring the XML
-- @return XML string of the object entry
local function toXml(plugin_conf, objectname, objecttype, object, tab)
    local xml = tab.."<"..objectname..">"
    kong.log.debug("Marshal "..objectname..", "..objecttype)

    if plugin_conf.models[objecttype] ~= nil and next(plugin_conf.models[objecttype]) ~= nil then
        kong.log.debug(tab.."Marshalling values from model")

        for _, value in pairs(plugin_conf.models[objecttype]) do
            kong.log.debug(value.name.." ("..type(object[value.name])..")")

            if value.type ~= nil and type(object[value.name]) == "table" then
                if object[value.name][1] ~= nil then
                    for _, arrayvalue in pairs(object[value.name]) do
                        xml = xml..toXml(plugin_conf, value.name, value.type, arrayvalue, tab.."  ")
                    end

                else
                    xml = xml..toXml(plugin_conf, value.name, value.type, object[value.name], tab.."  ")

                end

            elseif object[value.name] ~= nil and object[value.name] ~= cjson.null then
                kong.log.debug(value.name..": "..tostring(object[value.name]).." ("..type(object[value.name])..")")
                xml = xml..tab.."  <"..value.name..">"..toXmlValue(object[value.name]).."</"..value.name..">\n"

            end
        end

        -- only with complex structures do we need a line break
        xml = xml.."\n"
    elseif object ~= nil and type(object) == "table" then
        for key, value in pairs(object) do
            kong.log.debug(tab.."Marshalling object directly: "..key)
            xml = xml..toXmlValue(tostring(value))
        end

    elseif object ~= nil then
        xml = xml..toXmlValue(tostring(object))

    else
        kong.log.debug(tab.."Null object received")

    end

    return xml..tab.."</"..objectname..">\n"
end

-- Create the sorted XML object
-- @param plugin_conf Plugin configuration
-- @param objecttype Type of object entry
-- @param object object entry
-- @return XML string of the object entry
local function toSortedXml(plugin_conf, objecttype, object)
    return toXml(plugin_conf, objecttype, objecttype, object, "")
end

-- Replacing a SOAP Fault Response
-- @param faultcode Error code (Client/Server)
-- @param faultstring Error name
-- @param detail Error description
-- @return Fault as XML string
local function build_SOAP_fault(faultcode, faultstring, detail)
    if detail == nil then
        -- replace 'nil' in the answer
        detail = ""
    end

    return [[
<soap:Fault>
<faultcode>]]..faultcode..[[</faultcode>
<faultstring xml:lang="en">]]..faultstring..[[</faultstring>
<detail>
]]..tostring(detail)..[[
</detail>
</soap:Fault>
]]
end

-- Adding the Target Namespace Abbreviation
-- @param xml SAOP Body without Target Namespace
-- @param targetNamespace Target Namespace Abbreviation
-- @return SAOP Body mit Target Namespace
local function addTargetNamespacePrefixToRootElement(xml, targetNamespace)
    if xml ~= nil then
        -- start tag
        xml = string.gsub( xml, "^[ \r\n]*<", "<"..targetNamespace..":" )

        -- end tag
        xml = string.gsub( xml, "</([^:<>!]*)>[ \r\n]*$", "</"..targetNamespace..":%1>" )
    end

    return xml
end

-- Conversion of the body as a Lua table to the SOAP body
-- @param plugin_conf Plugin configuration
-- @param table_response Body as Lua table
-- @param response_code HTTP response code
-- @param RequestAction OperationId
-- @param targetNamespace Target Namespace Abbreviation
-- @param soap Operation Mapping
-- @return SOAP Body as XML String
local function build_XML(plugin_conf, table_response, response_code, RequestAction, targetNamespace, soap)

    -- Interception of Client Errors
    if tonumber(string.sub(response_code, 1, 1)) == 4 then
        local fault_detail

        if soap.fault400 ~= nil then
            local status
            status, fault_detail = pcall(toXml, plugin_conf, soap.fault400.name, soap.fault400.type, table_response, "")
            if not status then
                error("Unable to build client fault response\n\t", fault_detail)
            end
        else
            fault_detail = cjson.encode(table_response)
        end

        if fault_detail ~= nil then
            fault_detail = addTargetNamespacePrefixToRootElement(fault_detail, targetNamespace)
        else
            fault_detail = "HTTP Code: "..response_code
        end

        return build_SOAP_fault('soap:Client', 'Client error has occurred', fault_detail)
    end

    -- Interception of Server Errors
    if tonumber(string.sub(response_code, 1, 1)) == 5 then
        local fault_detail

        if soap.fault500 ~= nil then
            local status
            status, fault_detail = pcall(toXml, plugin_conf, soap.fault500.name, soap.fault500.type, table_response, "")
            if not status then
                error("Unable to build server fault response\n\t", fault_detail)
            end
        else
            fault_detail = cjson.encode(table_response)
        end

        if fault_detail ~= nil then
            fault_detail = addTargetNamespacePrefixToRootElement(fault_detail, targetNamespace)
        end

        return build_SOAP_fault('soap:Server', 'Server error has occurred', fault_detail)
    end

    -- Create the sorted XML object
    local status, xml_response = pcall(toSortedXml, plugin_conf, soap.response, table_response)
    if not status then
        error("Unable to build xml response\n\t", xml_response)
    end

    xml_response = [[
<]]..targetNamespace..":"..RequestAction.."_OutputMessage"..[[>
]]..xml_response..[[
</]]..targetNamespace..":"..RequestAction.."_OutputMessage"..[[>
]]

    return xml_response
end

-- Creating the SOAP response
-- @param xml_response SOAP Body as XML String
-- @param namespaces Necessary namespaces
-- @return SOAP response as XML string
local function build_SOAP(xml_response, namespaces)
    -- Insert XML response to SOAP template
    local soap_response = [[
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"]]

    for key, value in pairs(namespaces) do
        soap_response = soap_response..[[ xmlns:]]..key..[[="]]..value..[["]]
    end

    soap_response = soap_response..[[>
<soap:Body>
]]..xml_response..[[
</soap:Body>
</soap:Envelope>]]

    return soap_response
end

-- Converting a String to a Hex String
-- @param str String
-- @return Hex String
local function toHex(str)
    return (
        str:gsub('.', function (cc)
            return string.format("%02x", string.byte(cc))
        end
        )
    )
end

-- Generating the SOAP Response
-- @param plugin_conf Plugin configuration
-- @param table_response REST response
-- @param response_code REST response code
-- @param RequestAction OperationId
-- @return SOAP response as XML string
function _M.generateResponse(plugin_conf, table_response, response_code, RequestAction)
    local responseContentType = kong.service.response.get_header("content-type")

    kong.log.debug("Response Content-Type: "..responseContentType)
    if responseContentType:find("zip") == nil then
        -- Decode JSON
        kong.log.debug("Found JSON response")
        kong.log.debug("Response Body: "..table_response)

        -- Convert numbers to a string to avoid rounding errors
        -- this is not distinguishable in the XML
        table_response = string.gsub(table_response, "(:+[ ]?)([0-9%.]+)( ?[,}]+)", "%1\"%2\"%3")

        table_response = cjson.decode(table_response)
    elseif table_response ~= nil and table_response ~= "" then
        -- the rest in hex because binary data
        kong.log.debug("Found binary response")
        local hex_response = toHex(table_response)

        kong.log.debug("HEX Response: "..hex_response)
        table_response = {
            response = hex_response
        }
    end

    if type(table_response) == "table" or table_response == nil then

        if table_response == nil then
            kong.log.debug("Empty response found")
            table_response = {}
        end

        -- Conversion of the body as a Lua table to the SOAP body
        local status, xml_response = pcall(build_XML, plugin_conf, table_response, response_code, RequestAction, plugin_conf.targetNamespace, plugin_conf.operations[RequestAction].soap)
        if not status then
            kong.log.warn("Unable to build XML body\n\t", xml_response)
            return table_response
        end

        -- Creating the SOAP response
        local status, soap_response = pcall(build_SOAP, xml_response, plugin_conf.namespaces)
        if not status then
            kong.log.err("Unable to build SOAP response\n\t", soap_response)
        else
            kong.log.debug("SOAP Response: "..soap_response)
        end

        return soap_response
    end

    -- Return of the REST response if no conversion to SOAP was possible.
    return table_response
end --]]

return _M