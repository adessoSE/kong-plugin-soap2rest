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

-- Grab pluginname from module name
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

local function check_rest_base_path(value)
    if value ~= "/" and not string.match(value, '^/.*/$') then
        return false, "must starts and ends with '/'"
    end

    return true
end

local function check_operation_mapping(value)
    if string.match(value, '^/.*') then
        return false, "rest path must never begin with '/'"
    end

    return true
end

local schema = {
    name = plugin_name,
    fields = {
        { consumer = typedefs.no_consumer },  -- this plugin cannot be configured on a consumer (typical for auth plugins)
        { protocols = typedefs.protocols_http },
        { config = {
            type = "record",
            fields = {
                {-- The base path of the rest api.
                    rest_base_path = {
                        type = "string",
                        required = true,
                        custom_validator = check_rest_base_path,
                    },
                },
                {-- The path of the OpenAPI file.
                    openapi_yaml_path = {
                        type = "string",
                        required = true,
                    },
                },
                {-- The path of the WSDL file.
                    wsdl_path = {
                        type = "string",
                        required = true,
                    },
                },
                {-- Array of json strings.
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

                --[[ Cached config data ]]
                {-- Raw wsdl content
                    wsdl_content = {
                        type = "string",
                    },
                },
                {-- Soap namespaces
                    namespaces = {
                        type = "map",
                        keys = { type = "string" },
                        values = { type = "string" },
                    },
                },
                {-- targetnamespace shortcut
                    targetNamespace = {
                        type = "string",
                    }
                },
                {-- Operation configutation
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
                {-- models configutation
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
                {-- Array of soap arrays
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
