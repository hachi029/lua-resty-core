-- Copyright (C) Yichun Zhang (agentzh)


local ffi = require "ffi"
local base = require "resty.core.base"


local C = ffi.C
local ffi_new = ffi.new
local ffi_str = ffi.string
local type = type
local error = error
local tostring = tostring
local setmetatable = setmetatable
local get_request = base.get_request
local get_string_buf = base.get_string_buf
local get_size_ptr = base.get_size_ptr
local new_tab = base.new_tab
local subsystem = ngx.config.subsystem


local ngx_lua_ffi_var_get
local ngx_lua_ffi_var_set


local ERR_BUF_SIZE = 256


ngx.var = new_tab(0, 0)


if subsystem == "http" then
    ffi.cdef[[
    int ngx_http_lua_ffi_var_get(ngx_http_request_t *r,
        const char *name_data, size_t name_len, char *lowcase_buf,
        int capture_id, char **value, size_t *value_len, char **err);

    int ngx_http_lua_ffi_var_set(ngx_http_request_t *r,
        const unsigned char *name_data, size_t name_len,
        unsigned char *lowcase_buf, const unsigned char *value,
        size_t value_len, unsigned char *errbuf, size_t *errlen);
    ]]

    ngx_lua_ffi_var_get = C.ngx_http_lua_ffi_var_get
    ngx_lua_ffi_var_set = C.ngx_http_lua_ffi_var_set

elseif subsystem == "stream" then
    ffi.cdef[[
    int ngx_stream_lua_ffi_var_get(ngx_stream_lua_request_t *r,
        const char *name_data, size_t name_len, char *lowcase_buf,
        int capture_id, char **value, size_t *value_len, char **err);

    int ngx_stream_lua_ffi_var_set(ngx_stream_lua_request_t *r,
        const unsigned char *name_data, size_t name_len,
        unsigned char *lowcase_buf, const unsigned char *value,
        size_t value_len, unsigned char *errbuf, size_t *errlen);
    ]]

    ngx_lua_ffi_var_get = C.ngx_stream_lua_ffi_var_get
    ngx_lua_ffi_var_set = C.ngx_stream_lua_ffi_var_set
end


local value_ptr = ffi_new("unsigned char *[1]")
local errmsg = base.get_errmsg_ptr()


-- ngx.var.VAR_NAME 获取变量名
-- ngx.var[1] 获取捕获变量名 $1 $2...
local function var_get(self, name)
    local r = get_request()
    if not r then
        error("no request found")
    end

    -- 一个size_t指针的长度
    local value_len = get_size_ptr()
    local rc
    -- ngx.var[1]， 正则表达式的匹配组$1 $2
    if type(name) == "number" then
        rc = ngx_lua_ffi_var_get(r, nil, 0, nil, name, value_ptr, value_len,
                                 errmsg)

    else
        if type(name) ~= "string" then
            error("bad variable name", 2)
        end

        local name_len = #name
        -- 获取一个字符串缓存，用于存放小写的name
        local lowcase_buf = get_string_buf(name_len)

        -- 使用小写的name,调用ngx_http_get_variable(r, &name, hash);
        rc = ngx_lua_ffi_var_get(r, name, name_len, lowcase_buf, 0, value_ptr,
                                 value_len, errmsg)
    end

    -- ngx.log(ngx.WARN, "rc = ", rc)

    if rc == 0 then -- NGX_OK
        -- https://luajit.org/ext_ffi_api.html
        -- str = ffi.string(ptr [,len])
        -- The Lua string is an (interned) copy of the data and bears no relation to the original data area anymore.
        return ffi_str(value_ptr[0], value_len[0])
    end

    if rc == -5 then  -- NGX_DECLINED
        return nil
    end

    if rc == -1 then  -- NGX_ERROR
        error(ffi_str(errmsg[0]), 2)
    end
end


-- ngx.var.VAR_NAME = xxx
local function var_set(self, name, value)
    local r = get_request()
    if not r then
        error("no request found")
    end

    -- name必须为string
    if type(name) ~= "string" then
        error("bad variable name", 2)
    end
    local name_len = #name

    local errlen = get_size_ptr()
    errlen[0] = ERR_BUF_SIZE
    -- 用于存放小写的name和error_msg
    local lowcase_buf = get_string_buf(name_len + ERR_BUF_SIZE)

    -- value的长度
    local value_len
    if value == nil then
        value_len = 0
    else
        if type(value) ~= 'string' then
            value = tostring(value)
        end
        value_len = #value
    end

    local errbuf = lowcase_buf + name_len
    local rc = ngx_lua_ffi_var_set(r, name, name_len, lowcase_buf, value,
                                   value_len, errbuf, errlen)

    -- ngx.log(ngx.WARN, "rc = ", rc)

    if rc == 0 then -- NGX_OK
        return
    end

    if rc == -1 then  -- NGX_ERROR
        error(ffi_str(errbuf, errlen[0]), 2)
    end
end


do
    -- ngx.var.VAR_NAME
    local mt = new_tab(0, 2)
    mt.__index = var_get
    mt.__newindex = var_set

    setmetatable(ngx.var, mt)
end


return {
    version = base.version
}
