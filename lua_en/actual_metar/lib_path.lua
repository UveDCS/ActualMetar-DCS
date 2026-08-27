-- lib_path.lua — locates the LuaSec payload (ssl.dll, OpenSSL DLLs,
-- ssl.lua, https.lua, cacert.pem) and hooks it onto package.cpath/path so
-- HTTPS can be done from the Mission Editor (DCS ships LuaSocket but NOT
-- LuaSec). Same mechanism used by dcs-sms (see its README, "Community
-- prefabs" section).
--
-- Search order:
--   1. Our own module folder (MissionEditor\modules\actual_metar\lib\) —
--      this is how the payload arrives via the OvGME package (which can
--      only copy files inside the DCS folder, not Saved Games), and also
--      how the .exe installer places it from this version onward.
--   2. <Saved Games>\DCS\actual-metar\lib\ — where older .exe installer
--      versions left it (kept for compatibility, nobody needs to reinstall).
--   3. <Saved Games>\DCS\dcs-sms\lib\ — reuses dcs-sms's payload if the
--      user already has it installed, to avoid asking twice.

local paths = require("actual_metar.paths")

local M = {}

local LIB_DIR = nil

-- Folder this very file lives in (MissionEditor\modules\actual_metar\),
-- computed with debug.getinfo instead of assuming a fixed path: works the
-- same whether the mod was installed via the .exe or by hand (OvGME).
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
