-- lib_path.lua — localiza el payload de LuaSec (ssl.dll, OpenSSL DLLs,
-- ssl.lua, https.lua, cacert.pem) y lo engancha a package.cpath/path para
-- poder hacer HTTPS desde el Mission Editor (DCS trae LuaSocket pero NO
-- LuaSec). Mismo mecanismo que usa dcs-sms (ver su README, seccion
-- "Community prefabs").
--
-- Busca primero en nuestra propia carpeta (<Saved Games>/DCS/actual-metar/lib/)
-- y, si no esta, reaprovecha la de dcs-sms si el usuario ya la tiene
-- instalada (<Saved Games>/DCS/dcs-sms/lib/) — evita pedirle que instale
-- el mismo payload dos veces.

local paths = require("actual_metar.paths")

local M = {}

local LIB_DIR = nil

function M.resolve()
    if LIB_DIR then return LIB_DIR end
    local base = paths.saved_games_dir()
    if not base then return nil end

    local own = base .. "actual-metar\\lib\\"
    local dcs_sms = base .. "dcs-sms\\lib\\"

    if paths.dir_exists(own) then
        LIB_DIR = own
    elseif paths.dir_exists(dcs_sms) then
        LIB_DIR = dcs_sms
    end
    return LIB_DIR
end

function M.apply()
    local dir = M.resolve()
    if not dir then return false end

    package.path = package.path .. ";" .. dir .. "?.lua"
    package.cpath = package.cpath .. ";" .. dir .. "?.dll"
    return true
end

M.LIB_DIR = function() return M.resolve() or "" end

return M
