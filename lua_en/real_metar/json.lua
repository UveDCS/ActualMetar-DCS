-- json.lua — minimal pure-Lua JSON decoder (decode only, that's all we
-- need: aviationweather.gov responses). Written from scratch for this
-- project, no external dependency. Small and unoptimized on purpose —
-- METAR responses are a few hundred bytes.

local M = {}

local function skip_ws(s, i)
    while i <= #s do
        local c = s:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then break end
        i = i + 1
    end
    return i
end

local decode_value -- forward declaration

local function decode_string(s, i)
    -- s:sub(i,i) == '"'
    i = i + 1
    local out = {}
    while true do
        local c = s:sub(i, i)
        if c == "" then error("unterminated string in JSON") end
        if c == '"' then
            return table.concat(out), i + 1
        elseif c == "\\" then
            local nc = s:sub(i + 1, i + 1)
            if nc == "n" then out[#out + 1] = "\n"; i = i + 2
            elseif nc == "t" then out[#out + 1] = "\t"; i = i + 2
            elseif nc == "r" then out[#out + 1] = "\r"; i = i + 2
            elseif nc == '"' then out[#out + 1] = '"'; i = i + 2
            elseif nc == "\\" then out[#out + 1] = "\\"; i = i + 2
            elseif nc == "/" then out[#out + 1] = "/"; i = i + 2
            elseif nc == "u" then
                local hex = s:sub(i + 2, i + 5)
                local code = tonumber(hex, 16) or 63
                -- Good enough for METAR text (ASCII range covers everything
                -- we care about); higher codepoints degrade to '?'.
                if code < 128 then
                    out[#out + 1] = string.char(code)
                else
                    out[#out + 1] = "?"
                end
                i = i + 6
            else
                out[#out + 1] = nc; i = i + 2
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
end

local function decode_number(s, i)
    local j = i
    while j <= #s and s:sub(j, j):match("[%d%.%-%+eE]") do
        j = j + 1
    end
    local numstr = s:sub(i, j - 1)
    return tonumber(numstr), j
end

local function decode_array(s, i)
    -- s:sub(i,i) == '['
    i = skip_ws(s, i + 1)
    local arr = {}
    if s:sub(i, i) == "]" then return arr, i + 1 end
    while true do
        local val
        val, i = decode_value(s, i)
        arr[#arr + 1] = val
        i = skip_ws(s, i)
        local c = s:sub(i, i)
        if c == "," then
            i = skip_ws(s, i + 1)
        elseif c == "]" then
            return arr, i + 1
        else
            error("expected ',' or ']' in JSON array at pos " .. i)
        end
    end
end

local function decode_object(s, i)
    -- s:sub(i,i) == '{'
    i = skip_ws(s, i + 1)
    local obj = {}
    if s:sub(i, i) == "}" then return obj, i + 1 end
    while true do
        i = skip_ws(s, i)
        if s:sub(i, i) ~= '"' then error("expected string key in JSON object at pos " .. i) end
        local key
        key, i = decode_string(s, i)
        i = skip_ws(s, i)
        if s:sub(i, i) ~= ":" then error("expected ':' in JSON object at pos " .. i) end
        i = skip_ws(s, i + 1)
        local val
        val, i = decode_value(s, i)
        obj[key] = val
        i = skip_ws(s, i)
        local c = s:sub(i, i)
        if c == "," then
            i = skip_ws(s, i + 1)
        elseif c == "}" then
            return obj, i + 1
        else
            error("expected ',' or '}' in JSON object at pos " .. i)
        end
    end
end

decode_value = function(s, i)
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == '"' then
        return decode_string(s, i)
    elseif c == "{" then
        return decode_object(s, i)
    elseif c == "[" then
        return decode_array(s, i)
    elseif c == "t" and s:sub(i, i + 3) == "true" then
        return true, i + 4
    elseif c == "f" and s:sub(i, i + 4) == "false" then
        return false, i + 5
    elseif c == "n" and s:sub(i, i + 3) == "null" then
        return nil, i + 4
    elseif c:match("[%d%-]") then
        return decode_number(s, i)
    else
        error("unexpected character in JSON at pos " .. i .. ": " .. tostring(c))
    end
end

function M.decode(s)
    if type(s) ~= "string" then error("json.decode expects a string") end
    local i = skip_ws(s, 1)
    local val = decode_value(s, i)
    return val
end

return M
