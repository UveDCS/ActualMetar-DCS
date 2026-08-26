-- init.lua — loaded by the require() patched into MissionEditor.lua.
-- Independent project from dcs-sms (its own "ACTUAL METAR" tab in the menu
-- bar). Outer pcall: if anything in this require chain fails, the Mission
-- Editor keeps starting up normally.

local ok, err = pcall(function()
    local version = require("actual_metar.version")
    log.write("actual_metar", log.INFO, "bootstrap (version " .. tostring(version) .. ")")

    -- Hook up the LuaSec payload (if available) to be able to do HTTPS.
    -- Without it, the "Get METAR" button will show a clear error instead
    -- of failing silently.
    pcall(function() require("actual_metar.lib_path").apply() end)

    require("actual_metar.menu").install()
    require("actual_metar.ticker").install()
end)
if not ok then
    log.write("actual_metar", log.ERROR, "init failed: " .. tostring(err))
end
