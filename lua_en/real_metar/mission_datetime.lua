-- mission_datetime.lua — computes ["date"] and ["start_time"] for the mission.
--
-- IMPORTANT (explicit user decision, not an oversight): the chosen time
-- (Local / Map / Custom) is written AS-IS into start_time, with no
-- conversion to UTC. Technically DCS interprets start_time as seconds
-- since midnight UTC (see metar-dcs-app for the original reasoning), but
-- the user's editor apparently displays that same literal value (Zulu) as
-- if it were the time, so choosing "12:20" = writing "12:20" = seeing
-- "12:20" in the editor, with no timezone-offset surprises. If the
-- astronomically-correct conversion is ever wanted back, it's in this
-- file's history.
--
-- We still need to know what time it is RIGHT NOW at the chosen map (for
-- the "Map" mode), and that does require handling real timezones with
-- their DST rules. Each map is defined as {standard_offset_hours, rule}
-- where rule is "none" (no DST), "eu" (last Sunday of March/October) or
-- "us" (2nd Sunday of March / 1st Sunday of November). The "Local" mode,
-- on the other hand, doesn't use any of these tables: it reads the PC's
-- clock directly (os.date("*t") without "!"), whatever timezone Windows
-- has configured - no special permissions required, it's a normal clock
-- read.
--
-- All day-of-week math uses a days-since-epoch algorithm (Howard Hinnant,
-- public domain) instead of local os.time()/os.date(), so it doesn't
-- depend on the timezone configured on the PC running DCS.

local M = {}

-- days_from_civil: days since 1970-01-01 (proleptic Gregorian). y/m/d with
-- m in 1..12. Standard Howard Hinnant algorithm (chrono-compatible).
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

-- 0=Sunday .. 6=Saturday
local function weekday_from_days(z)
    return (z + 4) % 7
end

local function days_in_month(y, m)
    local dim = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if m == 2 and ((y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0) then return 29 end
    return dim[m]
end

-- Returns the day of month of the nth Sunday (n=1..5) of y/m. Negative n
-- (-1) = last Sunday of the month.
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

-- Is DST active at unix_utc (seconds since epoch) for this rule?
-- std_offset_h is the offset (hours) in STANDARD time (no DST).
local function is_dst_active(unix_utc, rule, std_offset_h)
    if rule == "none" then return false end

    local d = os.date("!*t", unix_utc)
    local year = d.year

    if rule == "eu" then
        -- Transition at exactly 01:00 UTC, the same across the whole EU.
        local start_day = nth_sunday(year, 3, -1)
        local end_day = nth_sunday(year, 10, -1)
        local start_utc = unix_from_civil(year, 3, start_day, 1, 0, 0)
        local end_utc = unix_from_civil(year, 10, end_day, 1, 0, 0)
        return unix_utc >= start_utc and unix_utc < end_utc
    elseif rule == "us" then
        -- Transition at 02:00 local time. At the start (2nd Sunday of
        -- March) local time is still standard; at the end (1st Sunday of
        -- November) local time is already daylight (std_offset_h + 1).
        local start_day = nth_sunday(year, 3, 2)
        local end_day = nth_sunday(year, 11, 1)
        local start_utc = unix_from_civil(year, 3, start_day, 2, 0, 0) - std_offset_h * 3600
        local end_utc = unix_from_civil(year, 11, end_day, 2, 0, 0) - (std_offset_h + 1) * 3600
        return unix_utc >= start_utc and unix_utc < end_utc
    end
    return false
end

-- offset_seconds_at(unix_utc, zone) -> total offset (seconds) to add to
-- UTC to get that zone's local time at that instant.
local function offset_seconds_at(unix_utc, zone)
    local dst = is_dst_active(unix_utc, zone.rule, zone.std_offset_h)
    local total_h = zone.std_offset_h + (dst and 1 or 0)
    return total_h * 3600, dst
end

-- civil_from_unix(unix_utc) -> table {year,month,day,hour,min,sec} (uses
-- os.date with "!" to stay independent of the system's timezone).
local function civil_from_unix(unix_utc)
    return os.date("!*t", unix_utc)
end

-- now_in_zone(zone) -> civil table {year,month,day,hour,min,sec} of the
-- real current time in that zone, and the offset (seconds) used.
function M.now_in_zone(zone)
    local now_utc = os.time()
    -- os.time() in Lua 5.1 interprets the given table as the system's
    -- local time; to get the real UTC instant we use os.time() with no
    -- arguments, which is already the Unix timestamp (timezone-independent
    -- by definition).
    local offset_s = offset_seconds_at(now_utc, zone)
    local civil = civil_from_unix(now_utc + offset_s)
    return civil, offset_s
end

-- compute(date_mode, date_value, time_mode, time_value, zone)
--   date_mode: "actual" | "custom". date_value: {year=, month=, day=} if custom.
--   time_mode: "local" | "map" | "custom". time_value: {hour=, min=, sec=} if custom.
--   zone: table with the map's REAL timezone {std_offset_h=, rule=} (only
--         used to know what time it is "now" in "map" mode).
-- Returns {date={Year=,Month=,Day=}, start_time=seconds (HH:MM:SS as-is,
-- no conversion), applied_label="YYYY-MM-DD HH:MM"} or nil, error_msg.
function M.compute(date_mode, date_value, time_mode, time_value, zone)
    if not zone then return nil, "unknown map timezone" end

    local now_civil_map = M.now_in_zone(zone)

    local y, mo, da
    if date_mode == "custom" then
        if not date_value then return nil, "missing custom date" end
        y, mo, da = date_value.year, date_value.month, date_value.day
    else
        y, mo, da = now_civil_map.year, now_civil_map.month, now_civil_map.day
    end

    local hh, mi, se
    if time_mode == "local" then
        -- The PC's clock as-is (no "!"): whatever Windows has configured.
        -- Requires no special permissions.
        local civil_local = os.date("*t")
        hh, mi, se = civil_local.hour, civil_local.min, civil_local.sec
    elseif time_mode == "map" then
        hh, mi, se = now_civil_map.hour, now_civil_map.min, now_civil_map.sec
    elseif time_mode == "custom" then
        if not time_value then return nil, "missing custom time" end
        hh, mi, se = time_value.hour, time_value.min, time_value.sec or 0
    else
        return nil, "unknown time mode: " .. tostring(time_mode)
    end

    -- No conversion: written as-is (see note at the top of this file).
    local start_time = hh * 3600 + mi * 60 + se

    return {
        date = { Year = y, Month = mo, Day = da },
        start_time = start_time,
        applied_label = string.format("%04d-%02d-%02d %02d:%02d", y, mo, da, hh, mi),
    }
end

return M
