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

local helpers = require "spec.helpers"
local xml2lua = require "xml2lua"
local handler = require "xmlhandler.tree"

--local inspect = require "inspect"

for _, strategy in helpers.each_strategy() do
    describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
        local client

        lazy_setup(function()
            local bp = helpers.get_db_utils(strategy, {
                "plugins",
                "routes",
                "services",
                "consumers"
            }, {PLUGIN_NAME})

            local service = bp.services:insert {
                name = "httpbin",
                url = "http://httpbin.org",
            }

            bp.routes:insert {
                name = "rest",
                paths = {"/"},
                service = {
                    id = service.id,
                },
                strip_path = false
            }

            local route = bp.routes:insert {
                name = "soap",
                paths = {"/soap"},
                service = {
                    id = service.id,
                },
                strip_path = false
            }

            assert(bp.plugins:insert {
                name = PLUGIN_NAME,
                route = {
                    id = route.id,
                },
                config = {
                    rest_base_path = "/",
                    wsdl_path = "/kong-plugin/spec/soap2rest/resources/test.wsdl",
                    openapi_yaml_path = "/kong-plugin/spec/soap2rest/resources/test.yaml",
                    expose_wsdl = true,
                    operation_mapping = {
                        GetStatusByCode = "status/{code}"
                    },
                    wsdl_content = "<?xml version=\"1.0\" encoding=\"utf-8\"?><definitions></definitions>",
                    namespaces = {
                        tns = "http://test/model",
                        xs = "http://www.w3.org/2001/XMLSchema"
                    },
                    targetNamespace = "tns",
                    operations = {
                        GetStatusByCode = {
                            rest = {
                                action = "get",
                                path = "/status/{code}",
                                request = {
                                    type = "application/json"
                                },
                                response = {
                                    type = "application/json"
                                }
                            },
                            soap = {
                                response = "TestDataObject",
                                fault400 = {
                                    name = "GetStatusByCode_400",
                                    type = "TestDataResponse400"
                                },
                                fault500 = {
                                    name = "GetStatusByCode_500",
                                    type = "Response500"
                                },
                            }
                        },
                    },
                    models = {
                        Response500 = {},
                        TestDataObject = {},
                        TestDataResponse400 = {},
                    }
                }
            })

            assert(helpers.start_kong {
                plugins = "bundled, "..PLUGIN_NAME,
                database   = strategy
            })
        end)

        lazy_teardown(function()
            helpers.stop_kong()
        end)

        before_each(function()
            client = helpers.proxy_ssl_client()
        end)

        after_each(function()
            if client then client:close() end
        end)

        describe("request", function()
            it("wsdl file", function()
                local res = assert(client:send {
                    method = "GET",
                    path = "/soap?WSDL"
                })

                assert.response(res).has.status(200)
                assert.is_same("<?xml version=\"1.0\" encoding=\"utf-8\"?><definitions></definitions>", res._cached_body)
            end)

            it("200 status code", function()
                local res = assert(client:send {
                    method = "POST",
                    path = "/soap/",
                    body = [[
                        <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:mod="http://test/model">
                        <soapenv:Header/>
                        <soapenv:Body>
                            <mod:GetStatusByCode_InputMessage>
                                <code>200</code>
                            </mod:GetStatusByCode_InputMessage>
                        </soapenv:Body>
                        </soapenv:Envelope>
                        ]]
                })
                assert.response(res).has.status(200)

                local template = handler:new()
                local parser = xml2lua.parser(template)
                parser:parse([[
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:tns="http://test/model" xmlns:xs="http://www.w3.org/2001/XMLSchema">
<soap:Body>
<tns:GetStatusByCode_OutputMessage>
<TestDataObject></TestDataObject>
</tns:GetStatusByCode_OutputMessage>
</soap:Body>
</soap:Envelope>]])
                local response = handler:new()
                parser = xml2lua.parser(response)
                parser:parse(res._cached_body)
                assert.is_same(template, response)
            end)

            it("400 status code", function()
                local res = assert(client:send {
                    method = "POST",
                    path = "/soap/",
                    body = [[
                        <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:mod="http://test/model">
                        <soapenv:Header/>
                        <soapenv:Body>
                            <mod:GetStatusByCode_InputMessage>
                                <code>400</code>
                            </mod:GetStatusByCode_InputMessage>
                        </soapenv:Body>
                        </soapenv:Envelope>
                        ]]
                })

                assert.response(res).has.status(200)
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
<tns:GetStatusByCode_400></tns:GetStatusByCode_400></detail>
</soap:Fault>
</soap:Body>
</soap:Envelope>]])
                local response = handler:new()
                parser = xml2lua.parser(response)
                parser:parse(res._cached_body)
                assert.is_same(template, response)
            end)

            it("500 status code", function()
                local res = assert(client:send {
                    method = "POST",
                    path = "/soap/",
                    body = [[
                        <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:mod="http://test/model">
                        <soapenv:Header/>
                        <soapenv:Body>
                            <mod:GetStatusByCode_InputMessage>
                                <code>500</code>
                            </mod:GetStatusByCode_InputMessage>
                        </soapenv:Body>
                        </soapenv:Envelope>
                        ]]
                })

                assert.response(res).has.status(500)
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
<tns:GetStatusByCode_500></tns:GetStatusByCode_500></detail>
</soap:Fault>
</soap:Body>
</soap:Envelope>]])
                local response = handler:new()
                parser = xml2lua.parser(response)
                parser:parse(res._cached_body)
                assert.is_same(template, response)
            end)
        end)
    end)
end
