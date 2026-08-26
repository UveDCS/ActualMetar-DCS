-- menu.lua — registra la entrada de menu superior "ACTUAL METAR", propia e
-- independiente de la de DCS-SMS (si tambien esta instalado, conviven sin
-- problema: solo se añade otro item mas a la barra). Tecnica identica a la
-- de dcs_sms_me/menu.lua (menuBar:insertItem), documentada alli como
-- descubierta releyendo me_menubar.lua.

local M = {}

local function log_err(msg)
    pcall(function() _G.log.write("actual_metar", _G.log.ERROR or 1, tostring(msg)) end)
end

local function add_top_level_menu()
    local ok, mb = pcall(require, "me_menubar")
    if not ok or not mb or not mb.menuBar then return false end
    if mb._actual_metar_top_added then return true end

    local menu_bar = mb.menuBar
    if type(menu_bar.insertItem) ~= "function" then return false end

    local ok_menu, Menu = pcall(require, "Menu")
    local ok_item, MenuBarItem = pcall(require, "MenuBarItem")
    if not (ok_menu and Menu and ok_item and MenuBarItem) then return false end

    local sibling_top = menu_bar.customize
    local sibling_menu = sibling_top and sibling_top.menu

    local menu = Menu.new()
    pcall(function()
        if sibling_menu and sibling_menu.getSkin and menu.setSkin then
            menu:setSkin(sibling_menu:getSkin())
        end
    end)
    function menu:onChange(item)
        if item and item.func then item.func() end
    end

    local item
    local ok_new, err = pcall(function() item = menu:newItem("Panel METAR") end)
    if not ok_new or not item then
        log_err("menu:newItem failed: " .. tostring(err))
        return false
    end
    pcall(function()
        local sib = sibling_menu and (sibling_menu.missionOptions or sibling_menu.mapOptions
            or sibling_menu.setPosition or sibling_menu.logbook)
        if sib and sib.getSkin and item.setSkin then item:setSkin(sib:getSkin()) end
    end)
    item.func = function()
        local ok2, err2 = pcall(function() require("actual_metar.window").toggle() end)
        if not ok2 then log_err("window.toggle failed: " .. tostring(err2)) end
    end

    local bar_item
    local ok_bar, bar_err = pcall(function() bar_item = MenuBarItem.new("ACTUAL METAR", menu) end)
    if not ok_bar or not bar_item then
        log_err("MenuBarItem.new failed: " .. tostring(bar_err))
        return false
    end
    pcall(function()
        if sibling_top and sibling_top.getSkin and bar_item.setSkin then
            bar_item:setSkin(sibling_top:getSkin())
        end
    end)
    pcall(function() menu_bar:insertItem(bar_item) end)

    mb._actual_metar_top_added = true
    return true
end

local function patch_menubar_show()
    local ok, mb = pcall(require, "me_menubar")
    if not ok or not mb or type(mb.show) ~= "function" then return false end
    if mb._actual_metar_show_patched then return true end

    local orig_show = mb.show
    mb.show = function(...)
        local result = orig_show(...)
        pcall(add_top_level_menu)
        return result
    end
    mb._actual_metar_show_patched = true
    return true
end

function M.install()
    if add_top_level_menu() then return "menu" end
    if patch_menubar_show() then return "menu" end
    log_err("me_menubar inaccessible - could not register ACTUAL METAR menu")
    return "failed"
end

return M
