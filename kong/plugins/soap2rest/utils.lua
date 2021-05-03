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

---[[ reads a file
function _M.read_file(path)
    local file = io.open(path, "r")
    local content = file:read("*a")
    file:close()
    return content
end --]]

---[[ checks if table contains value
function _M.has_value (tab, val)
    if tab ~= nil then
        for index, value in ipairs(tab) do
            if value == val then
                return true
            end
        end
    end

    return false
end --]]

return _M