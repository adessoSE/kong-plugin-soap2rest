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

local plugin_handler = require("kong.plugins."..PLUGIN_NAME..".handler")

describe(PLUGIN_NAME .. ": (handler)", function()
    local old_ngx = _G.ngx
    local mock_config
    local handler

    before_each(function()
        local stubbed_ngx = {
            ERR = "ERROR:",
            header = {},
            log = function(...) end,
            say = function(...) end,
            exit = function(...) end
        }

        _G.ngx = stubbed_ngx
        stub(stubbed_ngx, "say")
        stub(stubbed_ngx, "exit")
        stub(stubbed_ngx, "log")

        stub(kong.log, "err")
        stub(kong.request, "get_headers")

        handler = plugin_handler()
    end)

    after_each(function()
        _G.ngx = old_ngx
    end)

    describe("when wsdl and openapi not parsed", function()
        before_each(function()
            mock_config = {
                rest_base_path = "/spec/",
                wsdl_path = "/kong-plugin/spec/soap2rest/resources/test.wsdl",
                openapi_yaml_path = "/kong-plugin/spec/soap2rest/resources/test.yaml",
                expose_wsdl = true,
            }
            handler:access(mock_config)
        end)

        it("does parse wsdl and openapi correct", function()
            assert.is_not_nil(mock_config.operations)
            assert.is_not_nil(mock_config.wsdl_content)
            assert.is_not_nil(mock_config.namespaces)
            assert.is_not_nil(mock_config.targetNamespace)
        end)
    end)

    describe("when wsdl and openapi already parsed", function()
        before_each(function()
            mock_config = {
                rest_base_path = "/spec/",
                wsdl_path = "/kong-plugin/spec/soap2rest/resources/test.wsdl",
                openapi_yaml_path = "/kong-plugin/spec/soap2rest/resources/test.yaml",
                expose_wsdl = true,
                operations = {
                    GetTestData = {
                        rest = {
                            action = "get",
                            path = "/spec/test/data",
                            request = {
                                type = "application/json"
                            },
                            response = {
                                type = "application/spec.api.v1+json"
                            }
                        },
                        soap = {
                            response = "TestDataObject",
                            fault400 = "GetTestData_400",
                            fault500 = "GetTestData_500"
                        }
                    },
                }
            }
            handler:access(mock_config)
        end)

        it("does parse wsdl and openapi correct", function()
            assert.is_not_nil(mock_config.operations)
            assert.is_nil(mock_config.wsdl_content)
            assert.is_nil(mock_config.namespaces)
            assert.is_nil(mock_config.targetNamespace)
        end)
    end)

end)