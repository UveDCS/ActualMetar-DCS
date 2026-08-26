-- metar_fetch.lua — orchestrates the METAR download+calculation without
-- blocking the editor: a coroutine that keeps yielding ('pending') until
-- the transport finishes. The caller must invoke Job:step() once per tick
-- (see ticker.lua), same as dcs_sms_me.community_fetch.

local transport = require("actual_metar.https_transport")
local json = require("actual_metar.json")
local weather_calc = require("actual_metar.weather_calc")

local M = {}
local Job = {}
Job.__index = Job

local API_URL = "https://aviationweather.gov/api/data/metar?ids=%s&format=json"

function M.new()
    return setmetatable({ co = nil, state = "idle", weather = nil, error = nil, req = nil }, Job)
end

function Job:debug()
    if self.req and self.req.debug then
        local ok, s = pcall(self.req.debug)
        if ok then return s end
    end
    return self.state
end

function Job:start(icao)
    icao = tostring(icao or ""):upper():gsub("%s+", "")
    if not icao:match("^[A-Z0-9]+$") or #icao < 3 or #icao > 4 then
        self.state = "error"
        self.error = "Invalid ICAO: " .. tostring(icao)
        return
    end

    self.state = "running"
    self.error = nil
    self.weather = nil

    self.co = coroutine.create(function()
        local url = string.format(API_URL, icao)
        local req = transport.request(url)
        self.req = req
        local body
        while true do
            local status, result = req.poll()
            if status == "done" then body = result; break end
            if status == "error" then error(tostring(result), 0) end
            coroutine.yield()
        end

        local ok, decoded = pcall(json.decode, body)
        if not ok then error("invalid response from aviationweather.gov: " .. tostring(decoded), 0) end
        if type(decoded) ~= "table" or decoded[1] == nil then
            error("no METAR available for " .. icao, 0)
        end

        local ok2, w = pcall(weather_calc.normalize, decoded[1])
        if not ok2 then error("error computing weather: " .. tostring(w), 0) end
        self.weather = w
    end)
end

function Job:step()
    if self.state ~= "running" or not self.co then return self.state end
    local ok, err = coroutine.resume(self.co)
    if not ok then
        self.state = "error"
        self.error = tostring(err)
        self.co = nil
        return self.state
    end
    if coroutine.status(self.co) == "dead" then
        self.state = "done"
        self.co = nil
    end
    return self.state
end

M.Job = Job
return M
