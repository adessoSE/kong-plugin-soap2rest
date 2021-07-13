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

local openapi_handler = require("kong.plugins."..PLUGIN_NAME..".openapi_handler")

describe(PLUGIN_NAME .. ": (openapi_handler)", function()
    local mock_config = {
        rest_base_path = "/spec/",
        openapi_yaml_path = "/kong-plugin/spec/soap2rest/resources/test.yaml",
        operation_mapping = {
            GetTestDataById = "test/data/{id}",
            PostTestDataById = "test/data/{id}"
        },
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
        }
    }

    openapi_handler.parse(mock_config)

    it("does parse GetTestData correct", function()
        assert.is_not_nil(mock_config.operations.GetTestData)
        assert.is_not_nil(mock_config.operations.GetTestData.rest)

        assert.is_same({
            action = "get",
            path = "/spec/test/data",
            request = {
                type = "application/json"
            },
            response = {
                type = "application/spec.api.v1+json"
            }
        }, mock_config.operations.GetTestData.rest)
    end)

    it("does parse GetTestDataById correct", function()
        assert.is_not_nil(mock_config.operations.GetTestDataById)
        assert.is_not_nil(mock_config.operations.GetTestDataById.rest)

        assert.is_same({
            action = "get",
            path = "/spec/test/data/{id}",
            request = {
                type = "application/json"
            },
            response = {
                type = "application/spec.api.v1+json"
            }
        }, mock_config.operations.GetTestDataById.rest)
    end)

    it("does parse PostTestData correct", function()
        assert.is_not_nil(mock_config.operations.PostTestData)
        assert.is_not_nil(mock_config.operations.PostTestData.rest)

        assert.is_same({
            action = "post",
            path = "/spec/test/data",
            request = {
                type = "multipart/mixed",
                encoding = {
                    file = "text/plain, text/csv",
                    meta = "application/spec.api.v1+json"
                }
            },
            response = {
                type = "application/spec.api.v1+json"
            }
        }, mock_config.operations.PostTestData.rest)
    end)

    it("does parse PostTestDataById correct", function()
        assert.is_not_nil(mock_config.operations.PostTestDataById)
        assert.is_not_nil(mock_config.operations.PostTestDataById.rest)

        assert.is_same({
            action = "post",
            path = "/spec/test/data/{id}"
        }, mock_config.operations.PostTestDataById.rest)
    end)

end)