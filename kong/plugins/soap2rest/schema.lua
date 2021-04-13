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
                { rest_base_path = {        -- The base path of the rest api.
                    type = "string",
                    required = true,
                    custom_validator = check_rest_base_path,
                }},
                { openapi_yaml_path = {     -- The path of the OpenAPI file.
                    type = "string",
                    required = true,
                }},
                { wsdl_path = {             -- The path of the WSDL file.
                    type = "string",
                    required = true,
                }},
                { operation_mapping = {     -- Array of json strings.
                    type = "map",
                    keys = {
                        type = "string",
                    },
                    values = {
                        type = "string",
                        custom_validator = check_operation_mapping,
                    },
                }},

                --[[ Cached config data ]]
                { wsdl_content = {          -- Raw wsdl content
                    type = "string",
                }},
                { namespaces = {            -- Soap namespaces
                    type = "map",
                    keys = { type = "string" },
                    values = { type = "string" },
                }},
                { targetNamespace = {       -- targetnamespace shortcut
                    type = "string",
                }},
                { operations = {            -- Operation configutation
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
                                                    }}
                                                }
                                            }}
                                        }
                                    }},
                                    { response = {
                                        type = "record",
                                        fields = {
                                            { type = {
                                                type = "string",
                                            }}
                                        }
                                    }}
                                }
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
                                    }}
                                }
                            }}
                        }
                    }
                }},
                { models = {                -- models configutation
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
                }}
            }
        },
        },
    },
}

return schema
