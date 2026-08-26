-- https_transport.lua — GET HTTPS no bloqueante, para no congelar el
-- Mission Editor (Lua PUC de un solo hilo). Puerto directo de la tecnica
-- de dcs-sms (tools/me-mod/lua/dcs_sms_me/community_transport.lua):
-- TCP crudo de LuaSocket + TLS de LuaSec hechos a mano en modo no
-- bloqueante, hablando HTTP/1.0, avanzando UN paso por poll() (bombeado
-- por actual_metar.ticker una vez por tick de UpdateManager via corutina).
--
-- Instrumentado con log.write("actual_metar", ...) en cada transicion de
-- stage y con un timeout por RELOJ (no por numero de polls, que depende de
-- lo rapido que tiquee UpdateManager y podia tardar minutos en saltar) para
-- poder diagnosticar exactamente donde se queda colgado si pasa.

local lib_path = require("actual_metar.lib_path")

local M = {}

local function log_info(msg)
    pcall(function() _G.log.write("actual_metar", _G.log.INFO or 3, tostring(msg)) end)
end

local ssl
local function load_ssl()
    if ssl ~= nil then return ssl end
    local ok, mod = pcall(require, "ssl")
    ssl = (ok and type(mod) == "table") and mod or false
    if not ssl then log_info("ssl (LuaSec) no disponible") end
    return ssl
end

function M.available()
    return load_ssl() ~= false
end

local function parse_url(url)
    local host, rest = tostring(url or ""):match("^https://([^/]*)(.*)$")
    if not host or host == "" then return nil end
    local port = 443
    local h, p = host:match("^(.-):(%d+)$")
    if h then host, port = h, tonumber(p) end
    if rest == "" then rest = "/" end
    return host, port, rest
end

local function split_response(raw)
    local head, body = raw:match("^(.-)\r\n\r\n(.*)$")
    if not head then head, body = raw, "" end
    local code = tonumber(head:match("^HTTP/%d%.%d%s+(%d%d%d)")) or 0
    return code, body
end

local TIMEOUT_SECONDS = 20
local RECV_CHUNK = 16384

-- request(url) -> req con :poll() -> 'pending' | 'done', body | 'error', msg
-- req.debug() -> string con el stage actual y segundos transcurridos, para
-- mostrar en la ventana mientras se espera.
function M.request(url)
    local mod = load_ssl()
    if not mod then
        return {
            poll = function() return "error", "LuaSec no instalado (ver README de actual-metar)" end,
            debug = function() return "sin LuaSec" end,
        }
    end
    local socket_ok, socket = pcall(require, "socket")
    if not socket_ok or type(socket) ~= "table" then
        return {
            poll = function() return "error", "LuaSocket no disponible" end,
            debug = function() return "sin LuaSocket" end,
        }
    end
    local host, port, path = parse_url(url)
    if not host then
        return {
            poll = function() return "error", "URL no es https: " .. tostring(url) end,
            debug = function() return "url invalida" end,
        }
    end

    log_info("fetch start host=" .. host .. " port=" .. tostring(port) .. " path=" .. path)

    local stage = "connect"
    local sock, conn
    local request = string.format(
        "GET %s HTTP/1.0\r\nHost: %s\r\nUser-Agent: actual-metar\r\nAccept: application/json\r\nConnection: close\r\n\r\n",
        path, host)
    local sent = 0
    local chunks = {}
    local polls = 0
    local start_time = os.time()
    local last_logged_stage = nil

    local function set_stage(s)
        if s ~= stage then
            stage = s
            if stage ~= last_logged_stage then
                log_info("fetch stage -> " .. stage .. " (poll " .. polls .. ", " .. (os.time() - start_time) .. "s)")
                last_logged_stage = stage
            end
        end
    end

    local function cleanup()
        if conn then pcall(function() conn:close() end)
        elseif sock then pcall(function() sock:close() end) end
    end

    local function step()
        if stage == "connect" then
            if not sock then
                local s, e = socket.tcp()
                if not s then return "error", "tcp(): " .. tostring(e) end
                sock = s
                sock:settimeout(0)
            end
            local r, e = sock:connect(host, port)
            if r then set_stage("wrap"); return "pending" end
            if e == "timeout" or e == "Operation already in progress"
                or e == "Operation now in progress" or e == "Invalid argument" then return "pending" end
            if e == "already connected" then set_stage("wrap"); return "pending" end
            return "error", "connect: " .. tostring(e)
        elseif stage == "wrap" then
            local c, e = mod.wrap(sock, {
                mode = "client",
                protocol = "any",
                cafile = lib_path.LIB_DIR() .. "cacert.pem",
                verify = "peer",
                options = "all",
            })
            if not c then return "error", "ssl.wrap: " .. tostring(e) end
            conn = c
            pcall(function() conn:sni(host) end)
            conn:settimeout(0)
            set_stage("handshake")
            return "pending"
        elseif stage == "handshake" then
            local r, e = conn:dohandshake()
            if r then set_stage("send"); return "pending" end
            if e == "wantread" or e == "wantwrite" or e == "timeout" then return "pending" end
            return "error", "handshake: " .. tostring(e)
        elseif stage == "send" then
            local i, e = conn:send(request, sent + 1)
            if i then
                sent = i
                if sent >= #request then set_stage("recv") end
                return "pending"
            end
            if e == "wantwrite" or e == "wantread" or e == "timeout" then return "pending" end
            return "error", "send: " .. tostring(e)
        elseif stage == "recv" then
            local data, e, partial = conn:receive(RECV_CHUNK)
            if data and #data > 0 then chunks[#chunks + 1] = data end
            if partial and #partial > 0 then chunks[#chunks + 1] = partial end
            if e == "closed" then
                cleanup()
                local code, body = split_response(table.concat(chunks))
                log_info("fetch done http=" .. tostring(code) .. " bytes=" .. #table.concat(chunks))
                if code ~= 200 then return "error", "HTTP " .. tostring(code) end
                return "done", body
            end
            if e == nil or e == "wantread" or e == "wantwrite" or e == "timeout" then
                return "pending"
            end
            return "error", "recv: " .. tostring(e)
        end
        return "error", "stage invalido"
    end

    local req = {}
    function req.poll()
        polls = polls + 1
        if os.time() - start_time > TIMEOUT_SECONDS then
            cleanup()
            log_info("fetch TIMEOUT at stage=" .. stage .. " after " .. polls .. " polls")
            return "error", string.format("timeout esperando respuesta (bloqueado en '%s' tras %ds)", stage, TIMEOUT_SECONDS)
        end
        local ok, status, payload = pcall(step)
        if not ok then
            cleanup()
            log_info("fetch EXCEPTION at stage=" .. stage .. ": " .. tostring(status))
            return "error", "transport: " .. tostring(status)
        end
        return status, payload
    end
    function req.debug()
        return string.format("%s (%ds, %d polls)", stage, os.time() - start_time, polls)
    end
    return req
end

return M
