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

local wsdl_handler = require("kong.plugins."..PLUGIN_NAME..".wsdl_handler")

describe(PLUGIN_NAME .. ": (wsdl_handler)", function()
    local mock_config = {
        wsdl_path = "/kong-plugin/spec/soap2rest/resources/test.wsdl"
    }

    wsdl_handler.parse(mock_config)

    it("does parse raw wsdl content correct", function()
        assert.is_not_nil(mock_config.wsdl_content)
    end)

    it("does parse used namespaces correct", function()
        assert.is_same({
            tns = "http://test/model",
            xs = "http://www.w3.org/2001/XMLSchema"
        },mock_config.namespaces)
    end)

    it("does parse target namespace correct", function()
        assert.is_same("tns", mock_config.targetNamespace)
    end)

    it("does parse soap operation correct", function()
        assert.is_same({
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
            GetTestDataById = {
                soap = {
                    response = "TestDataObject",
                    fault500 = {
                        name = "GetTestDataById_500",
                        type = "Response500"
                    },
                }
            },
            PostTestData = {
                soap = {
                    response = "TestDataObject",
                    fault400 = {
                        name = "PostTestData_400",
                        type = "TestDataResponse400"
                    },
                }
            },
            PostTestDataById = {
                soap = {
                    response = "TestDataObject"
                }
            }
        }, mock_config.operations)
    end)

    it("does parse soap models correct", function()
        assert.is_same({
            GetTestData_OutputMessage = {
                {
                    name = "TestDataObject",
                    type = "TestDataObject"
                },
            },
            PostTestDataById_InputMessage = {
                {
                    name = "id",
                },
            },
            PostTestDataById_OutputMessage = {
                {
                    name = "body",
                    type = "TestDataObject"
                },
            },
            PostTestData_InputMessage = {
                {
                    name = "body",
                    type = "TestDataObject"
                },
            },
            Response500 = {
                {
                    name = "id"
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
        }, mock_config.models)
    end)

end)