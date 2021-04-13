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

---[[ builds sorted xml data
local function toXml(plugin_conf, objectname, objecttype, object, tab)
    local xml = tab.."<"..objectname..">\n"

    if plugin_conf.models[objecttype] ~= nil then
        for _, value in pairs(plugin_conf.models[objecttype]) do
            if value.type ~= nil and type(object[value.name]) == "table" then
                if object[value.name][1] ~= nil then
                    for _, arrayvalue in pairs(object[value.name]) do
                        xml = xml..toXml(plugin_conf, value.name, value.type, arrayvalue, tab.."  ")
                    end
                else
                    xml = xml..toXml(plugin_conf, value.name, value.type, object[value.name], tab.."  ")
                end
            else
                xml = xml..tab.."  <"..value.name..">"..(object[value.name] ~= nil and object[value.name] or "").."</"..value.name..">\n"
            end
        end
    end

    return xml..tab.."</"..objectname..">\n"
end --]]

---[[ builds sorted xml data
local function toSortedXml(plugin_conf, objecttype, object)
    return toXml(plugin_conf, objecttype, objecttype, object, "")
end --]]

---[[ builds the SOAP fault response
local function build_SOAP_fault(faultcode, faultstring, detail)
    return [[
<soap:Fault>
<faultcode>]]..faultcode..[[</faultcode>
<faultstring xml:lang="en">]]..faultstring..[[</faultstring>
<detail>
]]..detail..[[
</detail>
</soap:Fault>
]]
end --]]

---[[ converts Lua table to XML response
local function build_XML(plugin_conf, table_response, response_code, RequestAction, targetNamespace, soap)

    if tonumber(string.sub(response_code, 1,1)) == 4 then
        local fault_detail = toXml(plugin_conf, soap.fault400.name, soap.fault400.type, table_response, "")
        fault_detail = string.gsub( fault_detail, "(<%/?)", "%1"..targetNamespace..":" )
        return build_SOAP_fault('soap:Client', 'Client error has occurred', fault_detail)
    end

    if tonumber(string.sub(response_code, 1,1)) == 5 then
        local fault_detail = toXml(plugin_conf, soap.fault500.name, soap.fault500.type, table_response, "")
        fault_detail = string.gsub( fault_detail, "(<%/?)", "%1"..targetNamespace..":" )
        return build_SOAP_fault('soap:Server', 'Server error has occurred', fault_detail)
    end

    -- Convert response to XML
    local xml_response = toSortedXml(plugin_conf, soap.response, table_response)

    xml_response = [[
<]]..RequestAction.."_OutputMessage"..[[>
]]..xml_response..[[
</]]..RequestAction.."_OutputMessage"..[[>
]]

    -- Add namespace shortname to xml response
    return string.gsub(xml_response, "(<%/?)", "%1"..targetNamespace..":" )
end --]]

---[[ builds the SOAP response
local function build_SOAP(xml_response, namespaces, targetNamespace)
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
end --]]

---[[ generates the SOAP response
function _M.generateResponse(plugin_conf, table_response, response_code, RequestAction)
    table_response = cjson.decode(table_response)

    if type(table_response) == "table" or table_response == nil then

        if table_response == nil then
            table_response = {}
        end

        local status, xml_response = pcall(build_XML, plugin_conf, table_response, response_code, RequestAction, plugin_conf.targetNamespace, plugin_conf.operations[RequestAction].soap)
        if not status then
            kong.log.warn("Unable to build XML body\n\t", xml_response)
            return table_response
        end

        local status, soap_response = pcall(build_SOAP, xml_response, plugin_conf.namespaces, plugin_conf.targetNamespace)
        if not status then
            kong.log.err("Unable to build SOAP response\n\t", soap_response)
        end

        return soap_response
    end

    return table_response
end --]]

return _M