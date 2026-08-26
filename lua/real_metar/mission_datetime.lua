-- mission_datetime.lua — calcula ["date"] y ["start_time"] de la mision.
--
-- IMPORTANTE (decision explicita del usuario, no un descuido): la hora
-- elegida (Local / Mapa / Personalizada) se escribe TAL CUAL en
-- start_time, sin convertirla a UTC. Tecnicamente DCS interpreta
-- start_time como segundos desde medianoche UTC (ver metar-dcs-app para el
-- razonamiento original), pero el editor del usuario aparentemente muestra
-- ese mismo valor literal (Zulu) como si fuera la hora, asi que "12:20"
-- elegido = "12:20" escrito = "12:20" visto en el editor, sin sorpresas de
-- desfase horario. Si se quisiera la conversion astronomicamente correcta
-- de vuelta, esta en el historial de este fichero.
--
-- Aun asi hace falta saber que hora es AHORA MISMO en el mapa elegido (para
-- el modo "Mapa"), y eso si requiere manejar zonas horarias reales con su
-- horario de verano. Cada mapa se define como {offset_horas_estandar,
-- regla} donde regla es "none" (sin horario de verano), "eu" (ultimo
-- domingo de marzo/octubre) o "us" (2o domingo de marzo / 1er domingo de
-- noviembre). El modo "Local" en cambio no usa ninguna de estas tablas:
-- lee directamente la hora del reloj del PC (os.date("*t") sin "!"), sea
-- cual sea la zona horaria que tenga configurada Windows - no requiere
-- permisos especiales, es una lectura de reloj normal.
--
-- Todo el calculo de dia-de-la-semana usa un algoritmo de dias-desde-epoca
-- (Howard Hinnant, dominio publico) en vez de os.time()/os.date() locales,
-- para no depender de la zona horaria configurada en el PC que corre DCS.

local M = {}

-- days_from_civil: dias desde 1970-01-01 (Gregoriano proleptico). y/m/d con
-- m en 1..12. Algoritmo estandar de Howard Hinnant (chrono-Compatible).
local function days_from_civil(y, m, d)
    y = (m <= 2) and (y - 1) or y
    local era
    if y >= 0 then era = math.floor(y / 400) else era = math.floor((y - 399) / 400) end
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function unix_from_civil(y, m, d, hh, mm, ss)
    return days_from_civil(y, m, d) * 86400 + hh * 3600 + mm * 60 + ss
end

-- 0=domingo .. 6=sabado
local function weekday_from_days(z)
    return (z + 4) % 7
end

local function days_in_month(y, m)
    local dim = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if m == 2 and ((y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0) then return 29 end
    return dim[m]
end

-- Devuelve el dia del mes del enesimo domingo (n=1..5) de y/m. n negativo
-- (-1) = ultimo domingo del mes.
local function nth_sunday(y, m, n)
    if n > 0 then
        local first_day_wd = weekday_from_days(days_from_civil(y, m, 1))
        local first_sunday = 1 + ((7 - first_day_wd) % 7)
        return first_sunday + (n - 1) * 7
    else
        local last_day = days_in_month(y, m)
        local last_day_wd = weekday_from_days(days_from_civil(y, m, last_day))
        return last_day - last_day_wd
    end
end

-- ¿DST activo en el instante unix_utc (segundos desde epoca) para esta
-- regla? std_offset_h es el offset (horas) en horario ESTANDAR (sin DST).
local function is_dst_active(unix_utc, rule, std_offset_h)
    if rule == "none" then return false end

    local d = os.date("!*t", unix_utc)
    local year = d.year

    if rule == "eu" then
        -- Transicion a la 01:00 UTC exacta, misma en toda la UE.
        local start_day = nth_sunday(year, 3, -1)
        local end_day = nth_sunday(year, 10, -1)
        local start_utc = unix_from_civil(year, 3, start_day, 1, 0, 0)
        local end_utc = unix_from_civil(year, 10, end_day, 1, 0, 0)
        return unix_utc >= start_utc and unix_utc < end_utc
    elseif rule == "us" then
        -- Transicion a las 02:00 hora local. Al empezar (2o domingo marzo)
        -- la hora local aun es estandar; al terminar (1er domingo nov) la
        -- hora local ya es de verano (std_offset_h + 1).
        local start_day = nth_sunday(year, 3, 2)
        local end_day = nth_sunday(year, 11, 1)
        local start_utc = unix_from_civil(year, 3, start_day, 2, 0, 0) - std_offset_h * 3600
        local end_utc = unix_from_civil(year, 11, end_day, 2, 0, 0) - (std_offset_h + 1) * 3600
        return unix_utc >= start_utc and unix_utc < end_utc
    end
    return false
end

-- offset_seconds_at(unix_utc, zone) -> offset total (segundos) a sumar a
-- UTC para obtener la hora local de esa zona en ese instante.
local function offset_seconds_at(unix_utc, zone)
    local dst = is_dst_active(unix_utc, zone.rule, zone.std_offset_h)
    local total_h = zone.std_offset_h + (dst and 1 or 0)
    return total_h * 3600, dst
end

-- civil_from_unix(unix_utc) -> tabla {year,month,day,hour,min,sec} (usa
-- os.date con "!" para que sea independiente de la zona del sistema).
local function civil_from_unix(unix_utc)
    return os.date("!*t", unix_utc)
end

-- now_in_zone(zone) -> tabla civil {year,month,day,hour,min,sec} de la
-- hora actual real en esa zona, y el offset (segundos) usado.
function M.now_in_zone(zone)
    local now_utc = os.time()
    -- os.time() en Lua 5.1 interpreta la tabla actual como local del
    -- sistema; para obtener el instante UTC real usamos el propio
    -- os.time() sin argumentos, que ya es el timestamp Unix (independiente
    -- de la zona del sistema por definicion).
    local offset_s = offset_seconds_at(now_utc, zone)
    local civil = civil_from_unix(now_utc + offset_s)
    return civil, offset_s
end

-- compute(date_mode, date_value, time_mode, time_value, zone)
--   date_mode: "actual" | "custom". date_value: {year=, month=, day=} si custom.
--   time_mode: "local" | "map" | "custom". time_value: {hour=, min=, sec=} si custom.
--   zone: tabla de la zona horaria REAL del mapa {std_offset_h=, rule=} (solo
--         se usa para saber que hora es "ahora" en el modo "map").
-- Devuelve {date={Year=,Month=,Day=}, start_time=segundos (HH:MM:SS tal
-- cual, sin conversion), applied_label="AAAA-MM-DD HH:MM"} o nil, error_msg.
function M.compute(date_mode, date_value, time_mode, time_value, zone)
    if not zone then return nil, "zona horaria del mapa desconocida" end

    local now_civil_map = M.now_in_zone(zone)

    local y, mo, da
    if date_mode == "custom" then
        if not date_value then return nil, "falta la fecha personalizada" end
        y, mo, da = date_value.year, date_value.month, date_value.day
    else
        y, mo, da = now_civil_map.year, now_civil_map.month, now_civil_map.day
    end

    local hh, mi, se
    if time_mode == "local" then
        -- Hora del reloj del PC tal cual (sin "!"): la que tenga Windows
        -- configurada, sea la que sea. No requiere permisos especiales.
        local civil_local = os.date("*t")
        hh, mi, se = civil_local.hour, civil_local.min, civil_local.sec
    elseif time_mode == "map" then
        hh, mi, se = now_civil_map.hour, now_civil_map.min, now_civil_map.sec
    elseif time_mode == "custom" then
        if not time_value then return nil, "falta la hora personalizada" end
        hh, mi, se = time_value.hour, time_value.min, time_value.sec or 0
    else
        return nil, "modo de hora desconocido: " .. tostring(time_mode)
    end

    -- Sin conversion: se escribe tal cual (ver nota al principio del fichero).
    local start_time = hh * 3600 + mi * 60 + se

    return {
        date = { Year = y, Month = mo, Day = da },
        start_time = start_time,
        applied_label = string.format("%04d-%02d-%02d %02d:%02d", y, mo, da, hh, mi),
    }
end

return M
