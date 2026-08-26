-- paths.lua — utilidades de rutas compartidas (Saved Games\DCS\real-metar\).

local M = {}

function M.saved_games_dir()
    local ok, lfs = pcall(require, "lfs")
    if ok and lfs and lfs.writedir then
        local ok2, dir = pcall(lfs.writedir)
        if ok2 and dir then return dir end
    end
    -- lfs.writedir() normalmente devuelve <Saved Games>\DCS\ directamente
    -- cuando se llama desde dentro del proceso de DCS/ME.
    return nil
end

function M.dir_exists(path)
    local ok, lfs = pcall(require, "lfs")
    if not ok or not lfs or not lfs.attributes then return false end
    local ok2, attr = pcall(lfs.attributes, path)
    return ok2 and attr ~= nil and attr.mode == "directory"
end

-- own_dir() -> <Saved Games>\DCS\real-metar\ (la crea si no existe).
function M.own_dir()
    local base = M.saved_games_dir()
    if not base then return nil end
    local dir = base .. "real-metar\\"
    if not M.dir_exists(dir) then
        local ok, lfs = pcall(require, "lfs")
        if ok and lfs and lfs.mkdir then pcall(lfs.mkdir, dir) end
    end
    return dir
end

return M
