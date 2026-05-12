-- Copyright (C) Yichun Zhang (agentzh)


local ffi = require "ffi"
local debug = require "debug"
local base = require "resty.core.base"
local misc = require "resty.core.misc"


local C = ffi.C
local register_getter = misc.register_ngx_magic_key_getter
local register_setter = misc.register_ngx_magic_key_setter
local registry = debug.getregistry()
local new_tab = base.new_tab
local ref_in_table = base.ref_in_table
local get_request = base.get_request
local FFI_NO_REQ_CTX = base.FFI_NO_REQ_CTX
local FFI_OK = base.FFI_OK
local error = error
local setmetatable = setmetatable
local type = type
local subsystem = ngx.config.subsystem


-- 获取ngx.ctx 在ctxs数组中的的索引值
local ngx_lua_ffi_get_ctx_ref
local ngx_lua_ffi_set_ctx_ref


if subsystem == "http" then
    ffi.cdef[[
    int ngx_http_lua_ffi_get_ctx_ref(ngx_http_request_t *r, int *in_ssl_phase,
        int *ssl_ctx_ref);
    int ngx_http_lua_ffi_set_ctx_ref(ngx_http_request_t *r, int ref);
    ]]

    ngx_lua_ffi_get_ctx_ref = C.ngx_http_lua_ffi_get_ctx_ref
    ngx_lua_ffi_set_ctx_ref = C.ngx_http_lua_ffi_set_ctx_ref

elseif subsystem == "stream" then
    ffi.cdef[[
    int ngx_stream_lua_ffi_get_ctx_ref(ngx_stream_lua_request_t *r,
        int *in_ssl_phase, int *ssl_ctx_ref);
    int ngx_stream_lua_ffi_set_ctx_ref(ngx_stream_lua_request_t *r, int ref);
    ]]

    ngx_lua_ffi_get_ctx_ref = C.ngx_stream_lua_ffi_get_ctx_ref
    ngx_lua_ffi_set_ctx_ref = C.ngx_stream_lua_ffi_set_ctx_ref
end


local _M = {
    _VERSION = base.version
}


-- use a new ctxs table to make LuaJIT JIT compiler happy to generate more
-- efficient machine code.
-- 全局表，存放所有的ngx.ctx表。每个request对应的ctx在ctxs中的索引存放在ngx_http_lua_ctx_t的ctx_ref中
local ctxs = {}
registry.ngx_lua_ctx_tables = ctxs


local get_ctx_table
do
    local in_ssl_phase = ffi.new("int[1]")
    local ssl_ctx_ref = ffi.new("int[1]")

    -- 当获取ngx.ctx时会执行到ngx表的__index方法，进而执行到此。返回ngx.ctx。 ctx应该是nil
    -- https://github.com/openresty/lua-resty-core#get_ctx_table
    -- ctx: use the ctx from caller instead of creating a new table
    function get_ctx_table(ctx)
        local r = get_request()

        if not r then
            error("no request found")
        end

        -- 获取ctx在本文件ctxs中的索引，这个索引存储在ngx_http_lua_ctx_t的ctx_ref中, in_ssl_phase和ssl_ctx_ref是出参
        local ctx_ref = ngx_lua_ffi_get_ctx_ref(r, in_ssl_phase, ssl_ctx_ref)
        if ctx_ref == FFI_NO_REQ_CTX then
            error("no request ctx found")
        end

        -- (一个请求首次获取ctx时为-2， 此后再次获取为一个正值)小于0表示还没有创建
        if ctx_ref < 0 then
            ctx_ref = ssl_ctx_ref[0]    -- ssl阶段创建的ctx
            if ctx_ref > 0 and ctxs[ctx_ref] then
                -- 此处说明ssl阶段已经创建了ngx.ctx表
                if in_ssl_phase[0] ~= 0 then    --仍在ssl*阶段
                    return ctxs[ctx_ref]
                end

                -- 非ssl阶段
                if not ctx then
                    ctx = new_tab(0, 4)
                end

                -- 设置当前阶段新建的ctx的元表为ssl阶段创建的ctx
                ctx = setmetatable(ctx, ctxs[ctx_ref])

            else
                -- 说明ssl阶段也没还没创建ngx.ctx
                if in_ssl_phase[0] ~= 0 then
                    -- 正处于ssl*阶段
                    if not ctx then
                        ctx = new_tab(1, 4)
                    end

                    -- to avoid creating another table, we assume the users
                    -- won't overwrite the `__index` key
                    ctx.__index = ctx

                elseif not ctx then
                    ctx = new_tab(0, 4)
                end
            end

            --将新创建的ctx放入ctxs数组中，返回在数组中的index
            ctx_ref = ref_in_table(ctxs, ctx)
            if ngx_lua_ffi_set_ctx_ref(r, ctx_ref) ~= FFI_OK then
                return nil
            end
            return ctx
        end
        return ctxs[ctx_ref]
    end
end
-- 参考ngx的元表__index方法
register_getter("ctx", get_ctx_table)   -- 注册ngx.ctx
_M.get_ctx_table = get_ctx_table             --注册方法resty.core.ctx.get_ctx_table


local function set_ctx_table(ctx)
    local ctx_type = type(ctx)
    if ctx_type ~= "table" then
        error("ctx should be a table while getting a " .. ctx_type)
    end

    local r = get_request()

    if not r then
        error("no request found")
    end

    local ctx_ref = ngx_lua_ffi_get_ctx_ref(r, nil, nil)
    if ctx_ref == FFI_NO_REQ_CTX then
        error("no request ctx found")
    end

    if ctx_ref < 0 then
        ctx_ref = ref_in_table(ctxs, ctx)
        ngx_lua_ffi_set_ctx_ref(r, ctx_ref)
        return
    end
    ctxs[ctx_ref] = ctx
end
register_setter("ctx", set_ctx_table)


return _M
