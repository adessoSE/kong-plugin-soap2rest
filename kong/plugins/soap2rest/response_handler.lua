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

---[[ convert value to xml compatible value. bad signs are escaped
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
end --]]

---[[ builds sorted xml data
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

        -- nur bei komplexen strukturen brauchen wir einen zeilenumbruch
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
end --]]

---[[ builds sorted xml data
local function toSortedXml(plugin_conf, objecttype, object)
    return toXml(plugin_conf, objecttype, objecttype, object, "")
end --]]

---[[ builds the SOAP fault response
local function build_SOAP_fault(faultcode, faultstring, detail)
    if detail == nil then
        -- nil sieht blöd aus im response
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
end --]]

---[[ add the tns to the root element
local function addTargetNamespacePrefixToRootElement(xml, targetNamespace)
    if xml ~= nil then
        -- start tag
        xml = string.gsub( xml, "^[ \r\n]*<", "<"..targetNamespace..":" )

        -- end tag
        xml = string.gsub( xml, "</([^:<>!]*)>[ \r\n]*$", "</"..targetNamespace..":%1>" )
    end

    return xml
end --]]

---[[ converts Lua table to XML response
local function build_XML(plugin_conf, table_response, response_code, RequestAction, targetNamespace, soap)

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

    -- Convert response to XML
    local status, xml_response = pcall(toSortedXml, plugin_conf, soap.response, table_response)
    if not status then
        error("Unable to build xml response\n\t", xml_response)
    end

    xml_response = [[
<]]..targetNamespace..":"..RequestAction.."_OutputMessage"..[[>
]]..xml_response..[[
</]]..targetNamespace..":"..RequestAction.."_OutputMessage"..[[>
]]

    -- Add namespace shortname to xml response
    return xml_response
end --]]

---[[ builds the SOAP response
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
end --]]

---[[ convert string to hex string
local function toHex(str)
    return (
        str:gsub('.', function (cc)
            return string.format("%02x", string.byte(cc))
        end
        )
    )
end --]]

---[[ generates the SOAP response
function _M.generateResponse(plugin_conf, table_response, response_code, RequestAction)
    local responseContentType = kong.service.response.get_header("content-type")

    kong.log.debug("Response Content-Type: "..responseContentType)
    if responseContentType:find("zip") == nil then
        -- json dekodieren
        kong.log.debug("Found JSON response")
        kong.log.debug("Response Body: "..table_response)

        -- zahlen als string umbauen, damit keine rundungsfehler auftreten
        -- das ist im XML nicht unterscheidbar
        table_response = string.gsub(table_response, "(:+[ ]?)([0-9%.]+)( ?[,}]+)", "%1\"%2\"%3")

        table_response = cjson.decode(table_response)
    elseif table_response ~= nil and table_response ~= "" then
        -- den rest in hex weil binärdaten
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

        local status, xml_response = pcall(build_XML, plugin_conf, table_response, response_code, RequestAction, plugin_conf.targetNamespace, plugin_conf.operations[RequestAction].soap)
        if not status then
            kong.log.warn("Unable to build XML body\n\t", xml_response)
            return table_response
        end

        local status, soap_response = pcall(build_SOAP, xml_response, plugin_conf.namespaces)
        if not status then
            kong.log.err("Unable to build SOAP response\n\t", soap_response)
        else
            kong.log.debug("SOAP Response: "..soap_response)
        end

        return soap_response
    end

    return table_response
end --]]

return _M