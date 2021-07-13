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

local PLUGIN_NAME = "soap2rest"

local helpers = require("spec.helpers")
local xml2lua = require "xml2lua"
local handler = require "xmlhandler.tree"

local response_handler = require("kong.plugins."..PLUGIN_NAME..".response_handler")

describe(PLUGIN_NAME .. ": (response_handler)", function()
    local mock_config = {
        namespaces = {
            tns = "http://test/model",
            xs = "http://www.w3.org/2001/XMLSchema"
        },
        targetNamespace = "tns",
        operations = {
            GetTestData = {
                soap = {
                    response = "TestDataObject",
                    fault400 = {
                        name = "GetTestData_400",
                        type = "TestDataResponse400"
                    },
                    fault500 = {
                        name = "GetTestData_500",
                        type = "Response500"
                    },
                }
            },
        },
        models = {
            Response500 = {
                {
                    name = "id"
                },
                {
                    name = "code"
                },
            },
            TestDataObject = {
                {
                    name = "id"
                },
                {
                    name = "meta",
                    type = "TestMetadata"
                },
            },
            TestMetadata = {
                {
                    name = "name"
                },
                {
                    name = "value"
                },
                {
                    name = "code",
                    type = "TestCode"
                },
            },
            TestDataResponse400 = {
                {
                    name = "id"
                },
            },
        }
    }

    before_each(function()
        stub(kong.service.response, "get_header")

        kong.service.response.get_header = function(key)
            return "application/json"
          end
    end)

    it("does convert GetTestData 200 response correct ", function()
        local soap_response = response_handler.generateResponse(mock_config, "{\"id\":12, \"meta\":{\"name\":\"test\", \"value\":1337, \"code\":200}}", 200, "GetTestData")
        local template = handler:new()
        local parser = xml2lua.parser(template)
        parser:parse([[
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:tns="http://test/model" xmlns:xs="http://www.w3.org/2001/XMLSchema">
<soap:Body>
<tns:GetTestData_OutputMessage>
<TestDataObject>  <id>12</id>
  <meta>    <name>test</name>
    <value>1337</value>
    <code>200</code>

  </meta>

</TestDataObject>
</tns:GetTestData_OutputMessage>
</soap:Body>
</soap:Envelope>]])
        local response = handler:new()
        parser = xml2lua.parser(response)
        parser:parse(soap_response)
        assert.is_same(template, response)
    end)

    it("does convert GetTestData 400 response correct ", function()
        local soap_response = response_handler.generateResponse(mock_config, "{\"id\":\"abc123\", \"code\":400, \"data\":\"Hello fault\"}", 400, "GetTestData")
        local template = handler:new()
        local parser = xml2lua.parser(template)
        parser:parse([[
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:tns="http://test/model" xmlns:xs="http://www.w3.org/2001/XMLSchema">
<soap:Body>
<soap:Fault>
<faultcode>soap:Client</faultcode>
<faultstring xml:lang="en">Client error has occurred</faultstring>
<detail>
<tns:GetTestData_400>  <id>abc123</id>

</tns:GetTestData_400></detail>
</soap:Fault>
</soap:Body>
</soap:Envelope>]])
        local response = handler:new()
        parser = xml2lua.parser(response)
        parser:parse(soap_response)
        assert.is_same(template, response)
    end)

    it("does convert GetTestData 404 response correct ", function()
        local soap_response = response_handler.generateResponse(mock_config, "{\"id\":\"abc123\", \"code\":404, \"data\":\"Hello fault\"}", 404, "GetTestData")
        local template = handler:new()
        local parser = xml2lua.parser(template)
        parser:parse([[
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:tns="http://test/model" xmlns:xs="http://www.w3.org/2001/XMLSchema">
<soap:Body>
<soap:Fault>
<faultcode>soap:Client</faultcode>
<faultstring xml:lang="en">Client error has occurred</faultstring>
<detail>
<tns:GetTestData_400>  <id>abc123</id>

</tns:GetTestData_400></detail>
</soap:Fault>
</soap:Body>
</soap:Envelope>]])
        local response = handler:new()
        parser = xml2lua.parser(response)
        parser:parse(soap_response)
        assert.is_same(template,response)
    end)

    it("does convert GetTestData 500 response correct ", function()
        local soap_response = response_handler.generateResponse(mock_config, "{\"id\":\"abc123\", \"code\":500, \"data\":\"Hello fault\"}", 500, "GetTestData")
        local template = handler:new()
        local parser = xml2lua.parser(template)
        parser:parse([[
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:tns="http://test/model" xmlns:xs="http://www.w3.org/2001/XMLSchema">
<soap:Body>
<soap:Fault>
<faultcode>soap:Server</faultcode>
<faultstring xml:lang="en">Server error has occurred</faultstring>
<detail>
<tns:GetTestData_500>  <id>abc123</id>
  <code>500</code>

</tns:GetTestData_500></detail>
</soap:Fault>
</soap:Body>
</soap:Envelope>]])
        local response = handler:new()
        parser = xml2lua.parser(response)
        parser:parse(soap_response)
        assert.is_same(template, response)
    end)

    it("does convert GetTestData 501 response correct ", function()
        local soap_response = response_handler.generateResponse(mock_config, "{\"id\":\"abc123\", \"code\":501, \"data\":\"Hello fault\"}", 501, "GetTestData")
        local template = handler:new()
        local parser = xml2lua.parser(template)
        parser:parse([[
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:tns="http://test/model" xmlns:xs="http://www.w3.org/2001/XMLSchema">
<soap:Body>
<soap:Fault>
<faultcode>soap:Server</faultcode>
<faultstring xml:lang="en">Server error has occurred</faultstring>
<detail>
<tns:GetTestData_500>  <id>abc123</id>
  <code>501</code>

</tns:GetTestData_500></detail>
</soap:Fault>
</soap:Body>
</soap:Envelope>]])
        local response = handler:new()
        parser = xml2lua.parser(response)
        parser:parse(soap_response)
        assert.is_same(template, response)
    end)

end)
