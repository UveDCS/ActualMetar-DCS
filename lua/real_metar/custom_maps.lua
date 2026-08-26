-- custom_maps.lua — lista de ICAOs añadidos a mano por el usuario en el
-- desplegable "Mapa", persistida entre sesiones de DCS como un fichero Lua
-- normal en <Saved Games>\DCS\real-metar\custom_icaos.lua (mismo estilo que
-- usa dcs-sms para sus propios ficheros de ajustes, p.ej. me_hotkeys.lua).
--
-- Los ICAOs añadidos así no tienen zona horaria real conocida (no sabemos
-- de donde es un aeropuerto que el usuario escribe a mano) — se guardan
-- con std_offset_h=0, rule="none" (UTC) como valor por defecto razonable;
-- el modo de hora "Mapa" para uno de estos mostrara la hora UTC actual, y
-- el usuario puede editarlo a mano en el fichero si conoce la zona real.

local paths = require("real_metar.paths")

local M = {}

local FILE_NAME = "custom_icaos.lua"

local function file_path()
    local dir = paths.own_dir()
    if not dir then return nil end
    return dir .. FILE_NAME
end

function M.load()
    local path = file_path()
    if not path then return {} end
    local chunk = loadfile(path)
    if not chunk then return {} end
    local ok, result = pcall(chunk)
    if ok and type(result) == "table" then return result end
    return {}
end

local function serialize(list)
    local parts = { "-- generado por REAL METAR - no editar mientras el editor este abierto\nreturn {\n" }
    for _, e in ipairs(list) do
        parts[#parts + 1] = string.format(
            "  { name = %q, icao = %q, std_offset_h = %s, rule = %q },\n",
            e.name or e.icao, e.icao, tostring(e.std_offset_h or 0), e.rule or "none")
    end
    parts[#parts + 1] = "}\n"
    return table.concat(parts)
end

function M.save(list)
    local path = file_path()
    if not path then return false, "no se pudo resolver Saved Games\\DCS\\" end
    local f, err = io.open(path, "w")
    if not f then return false, tostring(err) end
    f:write(serialize(list))
    f:close()
    return true
end

-- add(icao, custom_name) -> ok, list_o_error. custom_name es opcional; si
-- se omite o esta en blanco se usa "Personalizado (ICAO)" por defecto.
function M.add(icao, custom_name)
    icao = tostring(icao or ""):upper():gsub("%s+", "")
    if not icao:match("^[A-Z0-9]+$") or #icao < 3 or #icao > 4 then
        return false, "ICAO invalido: " .. tostring(icao)
    end
    local list = M.load()
    for _, e in ipairs(list) do
        if e.icao == icao then return false, "ese ICAO ya esta en la lista" end
    end
    custom_name = tostring(custom_name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if custom_name == "" then custom_name = "Personalizado (" .. icao .. ")" end
    table.insert(list, {
        name = custom_name,
        icao = icao,
        std_offset_h = 0,
        rule = "none",
    })
    local ok, err = M.save(list)
    if not ok then return false, err end
    return true, list
end

-- remove(icao) -> ok, list_o_error
function M.remove(icao)
    icao = tostring(icao or ""):upper()
    local list = M.load()
    local new_list, removed = {}, false
    for _, e in ipairs(list) do
        if e.icao == icao then
            removed = true
        else
            new_list[#new_list + 1] = e
        end
    end
    if not removed then return false, "ese ICAO no esta en la lista de personalizados" end
    local ok, err = M.save(new_list)
    if not ok then return false, err end
    return true, new_list
end

return M
