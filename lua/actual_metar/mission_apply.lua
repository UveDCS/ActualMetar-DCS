-- mission_apply.lua — escribe los valores ya calculados (weather_calc +
-- mission_datetime) directamente en la tabla `mission` en memoria del
-- Mission Editor (require('me_mission').mission). A diferencia de
-- metar-dcs-app (que edita el .miz como zip/texto porque no hay proceso
-- vivo del editor), aqui mutamos la tabla Lua real: el editor la sirve tal
-- cual al pulsar Guardar.

local M = {}

-- apply_weather(mission, w) — w es la tabla que devuelve weather_calc.normalize
function M.apply_weather(mission, w)
    local weather = mission.weather
    if type(weather) ~= "table" then
        return false, "mission.weather no existe o no es una tabla"
    end

    weather.qnh = w.qnh
    weather.temperature = w.temperature
    weather.groundTurbulence = w.ground_turbulence

    if type(weather.wind) == "table" then
        local function set_alt(key, altdata)
            local a = weather.wind[key]
            if type(a) == "table" then
                a.speed = altdata.speed
                a.dir = altdata.dir
            end
        end
        set_alt("atGround", w.wind.ground)
        set_alt("at2000", w.wind.at2000)
        set_alt("at8000", w.wind.at8000)
    end

    local notes = {}
    if type(weather.clouds) == "table" then
        local clouds = weather.clouds
        clouds.density = w.clouds.density
        clouds.base = w.clouds.base
        clouds.thickness = w.clouds.thickness
        clouds.iprecptns = w.clouds.iprecptns
        -- Se escribe siempre, exista ya la clave o no: anadir una clave a
        -- una tabla Lua es seguro, y DCS solo lee las claves que conoce -
        -- una mision "en blanco" recien creada puede no traer ["preset"]
        -- todavia (no se ha tocado nunca el dialogo nativo de Weather), y
        -- antes eso hacia que se cayera al modelo dinamico sin necesidad.
        clouds.preset = w.clouds.preset or ""
    end

    if type(weather.visibility) == "table" then
        weather.visibility.distance = w.visibility_m
    end

    weather.enable_fog = w.fog.enable
    if type(weather.fog) == "table" then
        weather.fog.thickness = w.fog.thickness
        weather.fog.visibility = w.fog.visibility
    end

    if type(weather.season) == "table" then
        weather.season.temperature = w.temperature
    end

    if w.name_label and weather.name ~= nil then
        weather.name = w.name_label
    end

    return true, notes
end

-- apply_datetime(mission, dt) — dt es la tabla que devuelve mission_datetime.compute
function M.apply_datetime(mission, dt)
    if type(mission.date) ~= "table" then
        return false, "mission.date no existe o no es una tabla"
    end
    mission.date.Year = dt.date.Year
    mission.date.Month = dt.date.Month
    mission.date.Day = dt.date.Day
    mission.start_time = dt.start_time
    return true
end

return M
