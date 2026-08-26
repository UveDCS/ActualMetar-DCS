-- dcs_maps.lua — puerto de metar-dcs-app/dcs_maps.py. Aeropuerto real de
-- referencia y zona horaria (offset estandar en horas + regla de horario de
-- verano: "none"/"eu"/"us") por mapa de DCS. rule="none" es una
-- simplificacion para mapas cuyo pais no aplica DST (o, en el caso de
-- Falklands, aplica DST de hemisferio sur que no estamos modelando todavia
-- — ver comentario abajo).

local M = {}

M.MAPS = {
    { id = "caucasus", name = "Caucasus", icao = "UGKO", airport = "Kutaisi Intl (Georgia)", std_offset_h = 4, rule = "none" },
    { id = "nevada", name = "Nevada (NTTR)", icao = "KLAS", airport = "Harry Reid Intl, Las Vegas", std_offset_h = -8, rule = "us" },
    { id = "normandy", name = "Normandy", icao = "LFRK", airport = "Caen-Carpiquet", std_offset_h = 1, rule = "eu" },
    { id = "persian_gulf", name = "Persian Gulf", icao = "OMDB", airport = "Dubai Intl", std_offset_h = 4, rule = "none" },
    { id = "channel", name = "The Channel", icao = "LFAC", airport = "Calais-Dunkerque", std_offset_h = 1, rule = "eu" },
    { id = "syria", name = "Syria", icao = "OSDI", airport = "Damascus Intl", std_offset_h = 3, rule = "none" },
    { id = "marianas", name = "Marianas", icao = "PGUM", airport = "Antonio B. Won Pat Intl, Guam", std_offset_h = 10, rule = "none" },
    -- Falklands realmente observa DST de hemisferio sur (UTC-4 -> UTC-3 en
    -- verano austral, sep-abr) que no implementamos; se usa el offset
    -- estandar (UTC-4) todo el año como aproximacion.
    { id = "falklands", name = "South Atlantic (Falklands)", icao = "EGYP", airport = "RAF Mount Pleasant", std_offset_h = -4, rule = "none" },
    { id = "sinai", name = "Sinai", icao = "HESH", airport = "Sharm El Sheikh Intl", std_offset_h = 2, rule = "none" },
    { id = "kola", name = "Kola Peninsula", icao = "ULMM", airport = "Murmansk", std_offset_h = 3, rule = "none" },
    { id = "afghanistan", name = "Afghanistan", icao = "OAKB", airport = "Kabul Intl", std_offset_h = 4.5, rule = "none" },
    { id = "iraq", name = "Iraq", icao = "ORBI", airport = "Baghdad Intl", std_offset_h = 3, rule = "none" },
    { id = "germany_cw", name = "Germany Cold War", icao = "ETAR", airport = "Ramstein AB", std_offset_h = 1, rule = "eu" },
}

M.EXTRA = {
    { id = "reus", name = "España — Reus", icao = "LERS", airport = "Reus Airport (Tarragona)", std_offset_h = 1, rule = "eu" },
}

function M.find_by_id(id)
    for _, m in ipairs(M.MAPS) do
        if m.id == id then return m end
    end
    for _, m in ipairs(M.EXTRA) do
        if m.id == id then return m end
    end
    return nil
end

-- Mapea el string interno mission.theatre de DCS a una entrada de M.MAPS.
-- MEJOR ESFUERZO: si el theatre real no coincide con esta tabla, la
-- ventana deja los campos editables para que el usuario los corrija (y así
-- sepamos qué string real hay que añadir aquí).
M.THEATRE_TO_ID = {
    Caucasus = "caucasus",
    Nevada = "nevada",
    Normandy = "normandy",
    PersianGulf = "persian_gulf",
    TheChannel = "channel",
    Syria = "syria",
    MarianaIslands = "marianas",
    Falklands = "falklands",
    SinaiMap = "sinai",
    Kola = "kola",
    Afghanistan = "afghanistan",
    Iraq = "iraq",
    Germany = "germany_cw",
}

function M.guess_from_theatre(theatre)
    local id = M.THEATRE_TO_ID[theatre]
    if not id then return nil end
    return M.find_by_id(id)
end

return M
