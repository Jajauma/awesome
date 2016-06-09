---------------------------------------------------------------------------
--- Utility module for menubar
--
-- @author Antonio Terceiro
-- @copyright 2009, 2011-2012 Antonio Terceiro, Alexander Yakushev
-- @release @AWESOME_VERSION@
-- @module menubar.utils
---------------------------------------------------------------------------

-- Grab environment
local io = io
local table = table
local ipairs = ipairs
local string = string
local screen = screen
local awful_util = require("awful.util")
local theme = require("beautiful")
local lgi = require("lgi")
local gio = lgi.Gio
local wibox = require("wibox")
local debug = require("gears.debug")

local utils = {}

-- NOTE: This desktop files module was written according to the following
-- freedesktop.org specification:
-- http://standards.freedesktop.org/desktop-entry-spec/desktop-entry-spec-1.0.html

-- Options section

--- Terminal which applications that need terminal would open in.
utils.terminal = 'xterm'

--- Name of the WM for the OnlyShownIn entry in the .desktop file.
utils.wm_name = "awesome"

--- Parse a .desktop file.
-- @param file The .desktop file.
-- @return A table with file entries.
function utils.parse_desktop_file(file)
    local program = { show = true, file = file }
    local desktop_entry = false

    -- Parse the .desktop file.
    -- We are interested in [Desktop Entry] group only.
    for line in io.lines(file) do
        if line:find("^%s*#") then
            -- Skip comments.
            (function() end)() -- I haven't found a nice way to silence luacheck here
        elseif not desktop_entry and line == "[Desktop Entry]" then
            desktop_entry = true
        else
            if line:sub(1, 1) == "[" and line:sub(-1) == "]" then
                -- A declaration of new group - stop parsing
                break
            end

            -- Grab the values
            for key, value in line:gmatch("(%w+)%s*=%s*(.+)") do
                program[key] = value
            end
        end
    end

    -- In case [Desktop Entry] was not found
    if not desktop_entry then return nil end

    -- In case the (required) 'Name' entry was not found
    if not program.Name or program.Name == '' then return nil end

    -- Don't show program if NoDisplay attribute is false
    if program.NoDisplay and string.lower(program.NoDisplay) == "true" then
        program.show = false
    end

    -- Only show the program if there is no OnlyShowIn attribute
    -- or if it's equal to utils.wm_name
    if program.OnlyShowIn ~= nil and not program.OnlyShowIn:match(utils.wm_name) then
        program.show = false
    end

    -- Look up for a icon.
    if program.Icon then
        program.icon_path = theme.get_icon_provider():find_icon_path(program.Icon)
    end

    -- Split categories into a table. Categories are written in one
    -- line separated by semicolon.
    if program.Categories then
        program.categories = {}
        for category in program.Categories:gmatch('[^;]+') do
            table.insert(program.categories, category)
        end
    end

    if program.Exec then
        -- Substitute Exec special codes as specified in
        -- http://standards.freedesktop.org/desktop-entry-spec/1.1/ar01s06.html
        if program.Name == nil then
            program.Name = '['.. file:match("([^/]+)%.desktop$") ..']'
        end
        local cmdline = program.Exec:gsub('%%c', program.Name)
        cmdline = cmdline:gsub('%%[fuFU]', '')
        cmdline = cmdline:gsub('%%k', program.file)
        if program.icon_path then
            cmdline = cmdline:gsub('%%i', '--icon ' .. program.icon_path)
        else
            cmdline = cmdline:gsub('%%i', '')
        end
        if program.Terminal == "true" then
            cmdline = utils.terminal .. ' -e ' .. cmdline
        end
        program.cmdline = cmdline
    end

    return program
end

--- Parse a directory with .desktop files recursively.
-- @tparam string dir_path The directory path.
-- @tparam function callback Will be fired when all the files were parsed
-- with the resulting list of menu entries as argument.
-- @tparam table callback.programs Paths of found .desktop files.
function utils.parse_dir(dir_path, callback)

    local function parser(dir, programs)
        local f = gio.File.new_for_path(dir)
        -- Except for "NONE" there is also NOFOLLOW_SYMLINKS
        local query = gio.FILE_ATTRIBUTE_STANDARD_NAME .. "," .. gio.FILE_ATTRIBUTE_STANDARD_TYPE
        local enum, err = f:async_enumerate_children(query, gio.FileQueryInfoFlags.NONE)
        if not enum then
            debug.print_error(err)
            return
        end
        local files_per_call = 100 -- Actual value is not that important
        while true do
            local list, enum_err = enum:async_next_files(files_per_call)
            if enum_err then
                debug.print_error(enum_err)
                return
            end
            for _, info in ipairs(list) do
                local file_type = info:get_file_type()
                local file_path = enum:get_child(info):get_path()
                if file_type == 'REGULAR' then
                    local program = utils.parse_desktop_file(file_path)
                    if program then
                        table.insert(programs, program)
                    end
                elseif file_type == 'DIRECTORY' then
                    parser(file_path, programs)
                end
            end
            if #list == 0 then
                break
            end
        end
        enum:async_close()
    end

    gio.Async.start(function()
        local result = {}
        parser(dir_path, result)
        callback(result)
    end)()
end

--- Compute textbox width.
-- @tparam wibox.widget.textbox textbox Textbox instance.
-- @tparam number|screen s Screen
-- @treturn int Text width.
function utils.compute_textbox_width(textbox, s)
    s = screen[s or mouse.screen]
    local w, _ = textbox:get_preferred_size(s)
    return w
end

--- Compute text width.
-- @tparam str text Text.
-- @tparam number|screen s Screen
-- @treturn int Text width.
function utils.compute_text_width(text, s)
    return utils.compute_textbox_width(wibox.widget.textbox(awful_util.escape(text)), s)
end

return utils

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
