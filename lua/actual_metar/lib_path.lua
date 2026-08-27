-- lib_path.lua — localiza el payload de LuaSec (ssl.dll, OpenSSL DLLs,
-- ssl.lua, https.lua, cacert.pem) y lo engancha a package.cpath/path para
-- poder hacer HTTPS desde el Mission Editor (DCS trae LuaSocket pero NO
-- LuaSec). Mismo mecanismo que usa dcs-sms (ver su README, seccion
-- "Community prefabs").
--
-- Orden de busqueda:
--   1. Nuestra propia carpeta de modulo (MissionEditor\modules\actual_metar\lib\)
--      — asi es como llega el payload via el paquete OvGME (que solo puede
--      copiar ficheros dentro de la carpeta de DCS, no en Saved Games) y
--      tambien como lo deja el instalador .exe desde esta version.
--   2. <Saved Games>\DCS\actual-metar\lib\ — donde lo dejaban versiones
--      anteriores del instalador .exe (se mantiene por compatibilidad, no
--      hace falta que nadie reinstale).
--   3. <Saved Games>\DCS\dcs-sms\lib\ — reaprovecha el payload de dcs-sms
--      si el usuario ya lo tiene instalado, para no pedirselo dos veces.

local paths = require("actual_metar.paths")

local M = {}

local LIB_DIR = nil

-- Carpeta donde vive este propio fichero (MissionEditor\modules\actual_metar\),
-- calculada con debug.getinfo en vez de asumir una ruta fija: funciona igual
-- si el mod se instalo via el .exe o copiando los ficheros a mano (OvGME).
local function own_module_dir()
    local source = debug.getinfo(1, "S").source
    source = source:gsub("^@", "")
    return source:match("^(.*[\\/])")
end

function M.resolve()
    if LIB_DIR then return LIB_DIR end

    local module_dir = own_module_dir()
    if module_dir and paths.dir_exists(module_dir .. "lib\\") then
        LIB_DIR = module_dir .. "lib\\"
        return LIB_DIR
    end

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
