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

local typedefs = require "kong.db.schema.typedefs"

local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

-- Check whether the REST API path begins and ends with a '/'.
-- @param value Path to the REST API
-- @return boolean
local function check_rest_base_path(value)
    if value ~= "/" and not string.match(value, '^/.*/$') then
        return false, "must starts and ends with '/'"
    end

    return true
end

-- Check that the specified path does not begin with a '/'.
-- @param value REST API Path of the Operation Mapping
-- @return boolean
local function check_operation_mapping(value)
    if string.match(value, '^/.*') then
        return false, "rest path must never begin with '/'"
    end

    return true
end

local schema = {
    name = plugin_name,
    fields = {
        { consumer = typedefs.no_consumer },  -- This plugin cannot be configured as a 'consumer'.
        { protocols = typedefs.protocols_http },
        { config = {
            type = "record",
            fields = {
                {-- Path to the linked REST API.
                    rest_base_path = {
                        type = "string",
                        required = true,
                        custom_validator = check_rest_base_path,
                    },
                },
                {-- Path to the OpenAPI file of the REST API.
                    openapi_yaml_path = {
                        type = "string",
                        required = true,
                    },
                },
                {-- Path to the WSDL file of the SOAP API.
                    wsdl_path = {
                        type = "string",
                        required = true,
                    },
                },
                {-- SOAP Operation Mappings
                    -- @key:    SOAP OperationId
                    -- @value:  REST Path with parameter
                    operation_mapping = {
                        type = "map",
                        keys = {
                            type = "string",
                        },
                        values = {
                            type = "string",
                            custom_validator = check_operation_mapping,
                        },
                    },
                },

                ------------------------------------------------------------------------------
                -- Cached configuration of the plugin
                ------------------------------------------------------------------------------
                -- IMPORTANT:   Do not configure these parameters via Kong, as they are
                --              automatically generated from the WSDL and the OpenAPI!
                ------------------------------------------------------------------------------

                {-- Content of the WSDL file
                    wsdl_content = {
                        type = "string",
                    },
                },
                {-- SOAP Namespaces Mapping
                    -- @key:    SOAP Namespace acronym
                    -- @value:  SOAP Namespace URL
                    namespaces = {
                        type = "map",
                        keys = { type = "string" },
                        values = { type = "string" },
                    },
                },
                {-- Target Namespace acronym (e.g. 'tns')
                    targetNamespace = {
                        type = "string",
                    }
                },
                {-- Configuration of the SOAP operations
                    -- @key:    SOAP OperationId
                    -- @value:  Interfaces Definition of the SOAP and REST APIs
                    operations = {
                        type = "map",
                        keys = { type = "string" },
                        values = {
                            type = "record",
                            fields = {
                                { rest = {
                                    type = "record",
                                    fields = {
                                        { action = {
                                            type = "string",
                                        }},
                                        { path = {
                                            type = "string",
                                        }},
                                        { request = {
                                            type = "record",
                                            fields = {
                                                { type = {
                                                    type = "string",
                                                }},
                                                { encoding = {
                                                    type = "record",
                                                    fields = {
                                                        { file = {
                                                            type = "string",
                                                        }},
                                                        { meta = {
                                                            type = "string",
                                                        }},
                                                    },
                                                }},
                                            },
                                        }},
                                        { response = {
                                            type = "record",
                                            fields = {
                                                { type = {
                                                    type = "string",
                                                }},
                                            },
                                        }},
                                    },
                                }},
                                { soap = {
                                    type = "record",
                                    fields = {
                                        { response = {
                                            type = "string",
                                        }},
                                        { fault400 = {
                                            type = "record",
                                            fields = {
                                                { name = {
                                                    type = "string",
                                                }},
                                                { type = {
                                                    type = "string",
                                                }},
                                            },
                                        }},
                                        { fault500 = {
                                            type = "record",
                                            fields = {
                                                { name = {
                                                    type = "string",
                                                }},
                                                { type = {
                                                    type = "string",
                                                }},
                                            },
                                        }},
                                    },
                                }},
                            },
                        },
                    },
                },
                {-- Configuration of the return types
                 -- Used to return the attributes in the SOAP responses in the correct order.
                    models = {
                        type = "map",
                        keys = { type = "string" },
                        values = {
                            type = "array",
                            elements = {
                                type = "record",
                                fields = {
                                    { name = {
                                        type = "string",
                                    }},
                                    { type = {
                                        type = "string",
                                    }},
                                },
                            },
                        },
                    },
                },
                {-- Collection of the names of all SOAP arrays
                    soap_arrays = {
                        type = "array",
                        default = {},
                        elements = {
                            type = "string",
                        },
                    },
                },
            }
        },
        },
    },
}

return schema
