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

--local inspect = require "inspect"

local _M = {}

-- Reading a file
-- @param path path of the file
-- @return content of the file
function _M.read_file(path)
    local file = io.open(path, "r")
    local content = file:read("*a")
    file:close()
    return content
end --]]

-- Checking whether an array contains an object
-- @param array Lua Array
-- @param object Objekt
-- @return boolean
function _M.has_value (array, object)
    if array ~= nil then
        for index, value in ipairs(array) do
            if value == object then
                return true
            end
        end
    end

    return false
end

return _M