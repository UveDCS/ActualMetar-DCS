-- ticker.lua — registra un callback en UpdateManager (una vez por tick del
-- editor) que bombea el job de descarga METAR activo, si lo hay. Mismo
-- mecanismo que usa dcs_sms_me.bridge para su propio tick.
--
-- IMPORTANTE: UpdateManager NO es una variable global preexistente - es un
-- modulo que hay que cargar con require('UpdateManager') (visto en el
-- codigo real de dcs_sms_me.bridge). Mirar _G.UpdateManager directamente
-- (como hacia una version anterior de este fichero) siempre da nil y por
-- eso el bombeo nunca arrancaba.
--
-- M.install() es reintentable e idempotente por si acaso, aunque con el
-- require correcto deberia funcionar ya desde el primer intento en
-- init.lua.

local M = {}
local installed = false

local function tick()
    local ok, win = pcall(require, "real_metar.window")
    if ok and win and win._poll_job then
        pcall(win._poll_job)
    end
    return false -- seguir registrado
end

function M.install()
    if installed then return true end

    local ok_req, UpdateManager = pcall(require, "UpdateManager")
    if not ok_req or type(UpdateManager) ~= "table" or type(UpdateManager.add) ~= "function" then
        pcall(function()
            _G.log.write("real_metar", _G.log.ERROR or 1,
                "require('UpdateManager') fallo o sin .add (ok=" .. tostring(ok_req) ..
                ", tipo=" .. type(UpdateManager) .. ")")
        end)
        return false
    end

    local ok, err = pcall(UpdateManager.add, tick)
    if not ok then
        pcall(function() _G.log.write("real_metar", _G.log.ERROR or 1, "UpdateManager.add fallo: " .. tostring(err)) end)
        return false
    end
    installed = true
    pcall(function() _G.log.write("real_metar", _G.log.INFO or 3, "ticker instalado en UpdateManager") end)
    return true
end

function M.is_installed()
    return installed
end

return M
