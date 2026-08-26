-- lib_path.lua — locates the LuaSec payload (ssl.dll, OpenSSL DLLs,
-- ssl.lua, https.lua, cacert.pem) and hooks it onto package.cpath/path so
-- HTTPS can be done from the Mission Editor (DCS ships LuaSocket but NOT
-- LuaSec). Same mechanism used by dcs-sms (see its README, "Community
-- prefabs" section).
--
-- Looks first in our own folder (<Saved Games>/DCS/real-metar/lib/) and,
-- if not there, reuses dcs-sms's if the user already has it installed
-- (<Saved Games>/DCS/dcs-sms/lib/) — avoids asking them to install the
-- same payload twice.

local paths = require("real_metar.paths")

local M = {}

local LIB_DIR = nil

function M.resolve()
    if LIB_DIR then return LIB_DIR end
    local base = paths.saved_games_dir()
    if not base then return nil end

    local own = base .. "real-metar\\lib\\"
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
