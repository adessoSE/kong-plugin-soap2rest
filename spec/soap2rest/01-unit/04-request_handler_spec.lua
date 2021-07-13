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

require("kong.plugins."..PLUGIN_NAME..".request_handler")

describe(PLUGIN_NAME .. ": (request_handler)", function()

    describe("convertGET", function()
        before_each(function()
            stub(kong.service.request, "set_raw_body")
            stub(kong.service.request, "clear_header")
            stub(kong.log, "debug")
            stub(kong.service.request, "set_path")
        end)

        it("does insert query param", function()
            local operation = {
                rest = {
                    path = "/status",
                },
            }
            local bodyValue = {
                query = "test",
            }

            spy.on(kong.service.request, "set_path")

            convertGET(operation, bodyValue)

            assert.spy(kong.service.request.set_path).was.called()
            assert.spy(kong.service.request.set_path).was.called_with("/status?query=test")
        end)

        it("does insert url param", function()
            local operation = {
                rest = {
                    path = "/status/{code}",
                },
            }
            local bodyValue = {
                code = "200",
            }

            spy.on(kong.service.request, "set_path")

            convertGET(operation, bodyValue)

            assert.spy(kong.service.request.set_path).was.called()
            assert.spy(kong.service.request.set_path).was.called_with("/status/200")
        end)

        it("does insert url param and query param", function()
            local operation = {
                rest = {
                    path = "/status/{code}",
                },
            }
            local bodyValue = {
                code = "200",
                query = "test",
            }

            spy.on(kong.service.request, "set_path")

            convertGET(operation, bodyValue)

            assert.spy(kong.service.request.set_path).was.called()
            assert.spy(kong.service.request.set_path).was.called_with("/status/200?query=test")
        end)

        it("does escape query param (space)", function()
            local operation = {
                rest = {
                    path = "/status",
                },
            }
            local bodyValue = {
                query = "test with space",
            }

            spy.on(kong.service.request, "set_path")

            convertGET(operation, bodyValue)

            assert.spy(kong.service.request.set_path).was.called()
            assert.spy(kong.service.request.set_path).was.called_with("/status?query=test%20with%20space")
        end)

        it("does escape query param (/)", function()
            local operation = {
                rest = {
                    path = "/status",
                },
            }
            local bodyValue = {
                query = "test/slash",
            }

            spy.on(kong.service.request, "set_path")

            convertGET(operation, bodyValue)

            assert.spy(kong.service.request.set_path).was.called()
            assert.spy(kong.service.request.set_path).was.called_with("/status?query=test%2Fslash")
        end)

        it("does escape query param (#)", function()
            local operation = {
                rest = {
                    path = "/status",
                },
            }
            local bodyValue = {
                query = "test#hash",
            }

            spy.on(kong.service.request, "set_path")

            convertGET(operation, bodyValue)

            assert.spy(kong.service.request.set_path).was.called()
            assert.spy(kong.service.request.set_path).was.called_with("/status?query=test%23hash")
        end)

        it("does escape query param (?)", function()
            local operation = {
                rest = {
                    path = "/status",
                },
            }
            local bodyValue = {
                query = "test?questionmark",
            }

            spy.on(kong.service.request, "set_path")

            convertGET(operation, bodyValue)

            assert.spy(kong.service.request.set_path).was.called()
            assert.spy(kong.service.request.set_path).was.called_with("/status?query=test%3Fquestionmark")
        end)

        it("does escape url param (space)", function()
            local operation = {
                rest = {
                    path = "/status/{code}",
                },
            }
            local bodyValue = {
                code = "test with space",
            }

            spy.on(kong.service.request, "set_path")

            convertGET(operation, bodyValue)

            assert.spy(kong.service.request.set_path).was.called()
            assert.spy(kong.service.request.set_path).was.called_with("/status/test%20with%20space")
        end)

        it("does escape url param (/)", function()
            local operation = {
                rest = {
                    path = "/status/{code}",
                },
            }
            local bodyValue = {
                code = "test/slash",
            }

            spy.on(kong.service.request, "set_path")

            convertGET(operation, bodyValue)

            assert.spy(kong.service.request.set_path).was.called()
            assert.spy(kong.service.request.set_path).was.called_with("/status/test%2Fslash")
        end)

        it("does escape url param (#)", function()
            local operation = {
                rest = {
                    path = "/status/{code}",
                },
            }
            local bodyValue = {
                code = "test#hash",
            }

            spy.on(kong.service.request, "set_path")

            convertGET(operation, bodyValue)

            assert.spy(kong.service.request.set_path).was.called()
            assert.spy(kong.service.request.set_path).was.called_with("/status/test%23hash")
        end)

        it("does escape url param (?)", function()
            local operation = {
                rest = {
                    path = "/status/{code}",
                },
            }
            local bodyValue = {
                code = "test?questionmark",
            }

            spy.on(kong.service.request, "set_path")

            convertGET(operation, bodyValue)

            assert.spy(kong.service.request.set_path).was.called()
            assert.spy(kong.service.request.set_path).was.called_with("/status/test%3Fquestionmark")
        end)
    end)

end)