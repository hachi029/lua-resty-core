-- Copyright (C) by OpenResty Inc.


local base = require "resty.core.base"
base.allows_subsystem("http")


local core_request = require "resty.core.request"
local set_req_header = core_request.set_req_header


local _M = { version = base.version }


-- syntax: ngx_resp.add_header(header_name, header_value)
-- The header_value could be either a string or a table.
function _M.add_header(key, value)
    set_req_header(key, value, false)
end


return _M
