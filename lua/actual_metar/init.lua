-- init.lua — cargado por el require() parcheado en MissionEditor.lua.
-- Proyecto independiente de dcs-sms (pestaña propia "ACTUAL METAR" en la
-- barra de menu). pcall exterior: si algo de esta cadena de require falla,
-- el Mission Editor sigue arrancando con normalidad.

local ok, err = pcall(function()
    local version = require("actual_metar.version")
    log.write("actual_metar", log.INFO, "bootstrap (version " .. tostring(version) .. ")")

    -- Engancha el payload de LuaSec (si esta disponible) para poder hacer
    -- HTTPS. Sin el, el boton "Obtener METAR" mostrara un error claro en
    -- vez de fallar en silencio.
    pcall(function() require("actual_metar.lib_path").apply() end)

    require("actual_metar.menu").install()
    require("actual_metar.ticker").install()
end)
if not ok then
    log.write("actual_metar", log.ERROR, "init failed: " .. tostring(err))
end
