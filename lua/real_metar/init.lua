-- init.lua — cargado por el require() parcheado en MissionEditor.lua.
-- Proyecto independiente de dcs-sms (pestaña propia "REAL METAR" en la
-- barra de menu). pcall exterior: si algo de esta cadena de require falla,
-- el Mission Editor sigue arrancando con normalidad.

local ok, err = pcall(function()
    local version = require("real_metar.version")
    log.write("real_metar", log.INFO, "bootstrap (version " .. tostring(version) .. ")")

    -- Engancha el payload de LuaSec (si esta disponible) para poder hacer
    -- HTTPS. Sin el, el boton "Obtener METAR" mostrara un error claro en
    -- vez de fallar en silencio.
    pcall(function() require("real_metar.lib_path").apply() end)

    require("real_metar.menu").install()
    require("real_metar.ticker").install()
end)
if not ok then
    log.write("real_metar", log.ERROR, "init failed: " .. tostring(err))
end
