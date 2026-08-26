-- ticker.lua — registers a callback with UpdateManager (once per editor
-- tick) that pumps the active METAR-download job, if any. Same mechanism
-- dcs_sms_me.bridge uses for its own tick.
--
-- IMPORTANT: UpdateManager is NOT a pre-existing global variable - it's a
-- module you have to load with require('UpdateManager') (seen in the real
-- dcs_sms_me.bridge source). Looking at _G.UpdateManager directly (as an
-- earlier version of this file did) always returns nil, which is why the
-- pump never started.
--
-- M.install() is retryable and idempotent just in case, although with the
-- correct require it should already succeed on the first attempt from
-- init.lua.

local M = {}
local installed = false

local function tick()
    local ok, win = pcall(require, "real_metar.window")
    if ok and win and win._poll_job then
        pcall(win._poll_job)
    end
    return false -- stay registered
end

function M.install()
    if installed then return true end

    local ok_req, UpdateManager = pcall(require, "UpdateManager")
    if not ok_req or type(UpdateManager) ~= "table" or type(UpdateManager.add) ~= "function" then
        pcall(function()
            _G.log.write("real_metar", _G.log.ERROR or 1,
                "require('UpdateManager') failed or has no .add (ok=" .. tostring(ok_req) ..
                ", type=" .. type(UpdateManager) .. ")")
        end)
        return false
    end

    local ok, err = pcall(UpdateManager.add, tick)
    if not ok then
        pcall(function() _G.log.write("real_metar", _G.log.ERROR or 1, "UpdateManager.add failed: " .. tostring(err)) end)
        return false
    end
    installed = true
    pcall(function() _G.log.write("real_metar", _G.log.INFO or 3, "ticker installed on UpdateManager") end)
    return true
end

function M.is_installed()
    return installed
end

return M
