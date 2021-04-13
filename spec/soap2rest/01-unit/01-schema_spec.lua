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

-- helper function to validate data against a schema
local validate do
    local validate_entity = require("spec.helpers").validate_plugin_config_schema
    local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

    function validate(data)
        return validate_entity(data, plugin_schema)
    end
end

describe(PLUGIN_NAME .. ": (schema)", function()

    it("does accept required fields", function()
        local ok, err = validate({
            rest_base_path = "/spec/",
            wsdl_path = "/kong-plugin/spec/soap2rest/resources/test.wsdl",
            openapi_yaml_path = "/kong-plugin/spec/soap2rest/resources/test.yaml",
            operation_mapping = {
                GetTestDataById = "test/data/{id}",
                PostTestDataById = "test/data/{id}"
            }
        })

        assert.is_nil(err)
        assert.is_truthy(ok)
    end)

    it("does not accept empty required fields", function()
        local ok, err = validate({})

        assert.is_same({
            ["config"] = {
                ["openapi_yaml_path"] = 'required field missing',
                ["rest_base_path"] = 'required field missing',
                ["wsdl_path"] = 'required field missing'
            }
        }, err)

        assert.is_falsy(ok)
    end)

    it("does not accept rest_base_path without '/' at the start", function()
        local ok, err = validate({
            rest_base_path = "spec/",
            wsdl_path = "/kong-plugin/spec/soap2rest/resources/test.wsdl",
            openapi_yaml_path = "/kong-plugin/spec/soap2rest/resources/test.yaml",
        })

        assert.is_same({
            ["config"] = {
                ["rest_base_path"] = 'must starts and ends with \'/\'',
            }
        }, err)

        assert.is_falsy(ok)
    end)

    it("does not accept rest_base_path without '/' at the end", function()
        local ok, err = validate({
            rest_base_path = "/spec",
            wsdl_path = "/kong-plugin/spec/soap2rest/resources/test.wsdl",
            openapi_yaml_path = "/kong-plugin/spec/soap2rest/resources/test.yaml",
        })

        assert.is_same({
            ["config"] = {
                ["rest_base_path"] = 'must starts and ends with \'/\'',
            }
        }, err)

        assert.is_falsy(ok)
    end)

    it("does not accept rest_base_path without '/' at the start and end", function()
        local ok, err = validate({
            rest_base_path = "spec",
            wsdl_path = "/kong-plugin/spec/soap2rest/resources/test.wsdl",
            openapi_yaml_path = "/kong-plugin/spec/soap2rest/resources/test.yaml",
        })

        assert.is_same({
            ["config"] = {
                ["rest_base_path"] = 'must starts and ends with \'/\'',
            }
        }, err)

        assert.is_falsy(ok)
    end)

    it("does accept accept operation_mapping rest path with '/' at the start", function()
        local ok, err = validate({
            rest_base_path = "/spec/",
            wsdl_path = "/kong-plugin/spec/soap2rest/resources/test.wsdl",
            openapi_yaml_path = "/kong-plugin/spec/soap2rest/resources/test.yaml",
            operation_mapping = {
                GetTestDataById = "test/data/{id}",
                PostTestDataById = "/test/data/{id}"
            }
        })

        assert.is_same({
            ["config"] = {
                ["operation_mapping"] = 'rest path must never begin with \'/\'',
            }
        }, err)

        assert.is_falsy(ok)
    end)

end)