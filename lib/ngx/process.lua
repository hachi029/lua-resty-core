-- Copyright (C) Yichun Zhang (agentzh)


local base = require "resty.core.base"
base.allows_subsystem('http', 'stream')

local ffi = require 'ffi'
local errmsg = base.get_errmsg_ptr()
local FFI_ERROR = base.FFI_ERROR
local ffi_str = ffi.string
local tonumber = tonumber
local subsystem = ngx.config.subsystem

if subsystem == 'http' then
    require "resty.core.phase"  -- for ngx.get_phase
end

local ngx_phase = ngx.get_phase

-- OpenResty 里的进程分为如下六种类型：
local process_type_names = {
    [0 ]  = "single",           --单一进程，即非 master/worker 模式；
    [1 ]  = "master",           --监控进程，即 master 进程；
    [2 ]  = "signaller",        --信号进程，即 “-s” 参数时的进程；
    [3 ]  = "worker",           --工作进程，最常用的进程，对外提供服务；
    [4 ]  = "helper",           --辅助进程，不对外提供服务，例如 cache 进程；
    [99]  = "privileged agent", --特权进程，OpenResty 独有的进程类型。
}
---关闭了所有的监听端口，特权进程不能接受请求，“rewrite_by_lua” “access_by_lua” “content_by_lua” “log_by_lua” 等请求处理相关的执行阶段没有意义，这些阶段里的代码在特权进程里都不会运行。
-- 但有一个阶段是它可以使用的，那就是 “init_worker_by_lua”，特权进程要做的工作就是 ngx.timer.* 启动若干个定时器，运行周期任务，
-- 通过共享内存等方式与其他 worker 进程通信，利用自己的 root 权限做其他 worker 进程想做而不能做的工作

local C = ffi.C
local _M = { version = base.version }

-- C.ngx_http_lua_ffi_enable_privileged_agent
local ngx_lua_ffi_enable_privileged_agent
-- C.ngx_http_lua_ffi_get_process_type
local ngx_lua_ffi_get_process_type
-- C.ngx_http_lua_ffi_process_signal_graceful_exit
local ngx_lua_ffi_process_signal_graceful_exit
-- C.ngx_http_lua_ffi_master_pid
local ngx_lua_ffi_master_pid

if subsystem == 'http' then
    ffi.cdef[[
        int ngx_http_lua_ffi_enable_privileged_agent(char **err,
            unsigned int connections);
        int ngx_http_lua_ffi_get_process_type(void);
        void ngx_http_lua_ffi_process_signal_graceful_exit(void);
        int ngx_http_lua_ffi_master_pid(void);
    ]]

    ngx_lua_ffi_enable_privileged_agent =
        C.ngx_http_lua_ffi_enable_privileged_agent
    ngx_lua_ffi_get_process_type = C.ngx_http_lua_ffi_get_process_type
    ngx_lua_ffi_process_signal_graceful_exit =
        C.ngx_http_lua_ffi_process_signal_graceful_exit
    ngx_lua_ffi_master_pid = C.ngx_http_lua_ffi_master_pid

else
    ffi.cdef[[
        int ngx_stream_lua_ffi_enable_privileged_agent(char **err,
            unsigned int connections);
        int ngx_stream_lua_ffi_get_process_type(void);
        void ngx_stream_lua_ffi_process_signal_graceful_exit(void);
        int ngx_stream_lua_ffi_master_pid(void);
    ]]

    ngx_lua_ffi_enable_privileged_agent =
        C.ngx_stream_lua_ffi_enable_privileged_agent
    ngx_lua_ffi_get_process_type = C.ngx_stream_lua_ffi_get_process_type
    ngx_lua_ffi_process_signal_graceful_exit =
        C.ngx_stream_lua_ffi_process_signal_graceful_exit
    ngx_lua_ffi_master_pid = C.ngx_stream_lua_ffi_master_pid
end


-- syntax: type_name = process_module.type()
function _M.type()
    -- C.ngx_http_lua_ffi_get_process_type
    local typ = ngx_lua_ffi_get_process_type()
    return process_type_names[tonumber(typ)]
end


-- syntax: ok, err = process_module.enable_privileged_agent(connections)
-- connections: sets the maximum number of simultaneous connections that can be opened by privileged agent process.
function _M.enable_privileged_agent(connections)
    if ngx_phase() ~= "init" then
        return nil, "API disabled in the current context"
    end

    connections = connections or 512

    if type(connections) ~= "number" or connections < 0 then
        return nil, "bad 'connections' argument: " ..
            "number expected and greater than 0"
    end

    -- C.ngx_http_lua_ffi_enable_privileged_agent
    local rc = ngx_lua_ffi_enable_privileged_agent(errmsg, connections)

    if rc == FFI_ERROR then
        return nil, ffi_str(errmsg[0])
    end

    return true
end


-- syntax: process_module.signal_graceful_exit()
function _M.signal_graceful_exit()
    ngx_lua_ffi_process_signal_graceful_exit()
end


-- syntax: pid = process_module.get_master_pid()
function _M.get_master_pid()
    local pid = ngx_lua_ffi_master_pid()
    if pid == FFI_ERROR then
        return nil
    end

    return tonumber(pid)
end


return _M
