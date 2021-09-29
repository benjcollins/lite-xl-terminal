-- mod-version:2 -- lite-xl 2.0
local core = require "core"
local keymap = require "core.keymap"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local View = require "core.view"

local process = require "process"

config.terminal = {
  shell = os.getenv("SHELL") or "/bin/sh",
  shell_args = {},
  split_direction = "down"
}

local TerminalView = View:extend()

local ESC = "\x1b"

local COLORS = {
    { ["dark"] = { common.color "#000000" }, ["bright"] = { common.color "#555753" }, ["name"] = "black" },
    { ["dark"] = { common.color "#cc0000" }, ["bright"] = { common.color "#ef2929" }, ["name"] = "red" },
    { ["dark"] = { common.color "#4e9a06" }, ["bright"] = { common.color "#8ae234" }, ["name"] = "green" },
    { ["dark"] = { common.color "#c4a000" }, ["bright"] = { common.color "#fce94f" }, ["name"] = "yellow" },
    { ["dark"] = { common.color "#3465a4" }, ["bright"] = { common.color "#729fcf" }, ["name"] = "blue" },
    { ["dark"] = { common.color "#75507b" }, ["bright"] = { common.color "#ad7fa8" }, ["name"] = "magenta" },
    { ["dark"] = { common.color "#06989a" }, ["bright"] = { common.color "#34e2e2" }, ["name"] = "cyan" },
    { ["dark"] = { common.color "#d3d7cf" }, ["bright"] = { common.color "#eeeeec" }, ["name"] = "white" },
}

local PASSTHROUGH_PATH = USERDIR .. "/plugins/lite-xl-terminal/terminal"
local CONNECT_MSG = "[Starting terminal...]\r\n\n"
local TERMINATION_MSG = "\r\n\n[Process ended with status %d]"

function TerminalView:new()
    TerminalView.super.new(self)
    self.scrollable = true

    local args = { PASSTHROUGH_PATH, config.terminal.shell }
    for _, arg in ipairs(config.terminal.shell_args) do
      table.insert(args, arg)
    end
    self.proc = assert(process.start(args, {
      stdin = process.REDIRECT_PIPE,
      stdout = process.REDIRECT_PIPE,
    }))

    self.columns = 80
    self.rows = 24
    self.buffer = {}
    self.cursor_col = 1
    self.cursor_row = 1
    self.saved_cursor = { col = 1, row = 1 }
    self.last_blink = system.get_time()
    self.cursor_visible = true
    self.blink_cursor = true
    self.blink_time = 0.2
    self.fg = style.text
    self.bg = style.background
    self.title = "Terminal"
    self.log = io.open("log.txt", "w")
    self.visible = true
    self.scroll_region_start = 1
    self.scroll_region_end = self.rows

    for col = 1, self.columns do
        self.buffer[col] = {}
        for row = 1, self.rows do
            self.buffer[col][row] = self:new_formatted_char(" ")
        end
    end

    self.escape_handler = {

        -- Cursor Positioning
        ["A"] = function(args)
            self.cursor_row = math.max(1, self.cursor_row - (args[1] or 1))
        end,
        ["B"] = function(args)
            self.cursor_row = math.min(self.rows, self.cursor_row + (args[1] or 1))
        end,
        ["C"] = function(args)
            self.cursor_col = math.min(self.columns, self.cursor_col + (args[1] or 1))
        end,
        ["D"] = function(args)
            self.cursor_col = math.max(1, self.cursor_col - (args[1] or 1))
        end,
        ["H"] = function(args)
            self.cursor_row = args[1] or 1
            self.cursor_col = args[2] or 1
        end,
        ["G"] = function(args)
            self.cursor_col = args[1] or 1
        end,
        ["d"] = function(args)
            self.cursor_row = args[1] or 1
        end,

        -- Text Modification
        ["@"] = function(args)
            local count = args[1] or 1
            for i = self.columns, self.cursor_col + count, -1 do
                self.buffer[i][self.cursor_row] = self.buffer[i - count][self.cursor_row]
            end
            for i = self.cursor_col, self.cursor_col + count - 1 do
                self.buffer[i][self.cursor_row].value = " "
            end
        end,
        ["P"] = function(args)
            local count = args[1] or 1
            for i = self.cursor_col + count, self.columns do
                self.buffer[i - count][self.cursor_row] = self.buffer[i][self.cursor_row]
            end
            for i = self.columns - count, self.columns do
                self.buffer[i][self.cursor_row].value = " "
            end
        end,
        ["K"] = function(args)
            self:delete_current_line(args[1] or 0)
        end,
        ["J"] = function(args)
            local mode = args[1] or 0
            self:delete_current_line(mode)
            local first = 1
            local last = self.rows
            if mode == 0 then
                first = self.cursor_row + 1
            elseif mode == 1 then
                last = self.cursor_row
            end
            for row = first, last do
                for col = 1, self.columns do
                    self.buffer[col][row] = self:new_formatted_char(" ")
                end
            end
        end,

        ["r"] = function(args)
            self.scroll_region_start = (args[1] or 1)
            self.scroll_region_end = (args[2] or self.rows)
        end,

        -- Text Formatting
        ["m"] = function(args)
            local i = 1
            args[1] = args[1] or 0
            while args[i] do
                local arg = args[i]

                if arg == 0 then
                    self.fg = style.text
                    self.bg = style.background

                elseif arg == 39 then
                    self.fg = style.text
                elseif arg == 49 then
                    self.bg = style.background

                elseif arg == 7 then
                    local temp = self.fg
                    self.fg = self.bg
                    self.bg = temp

                -- elseif arg == 27 and self.inverted then
                --     local temp = self.fg
                --     self.fg = self.bg
                --     self.bg = temp
                --     self.inverted = false

                elseif arg > 29 and arg < 38 then
                    self.fg = COLORS[arg - 29].dark
                elseif arg > 39 and arg < 48 then
                    self.bg = COLORS[arg - 39].dark
                elseif arg > 89 and arg < 98 then
                    self.fg = COLORS[arg - 89].bright
                elseif arg > 99 and arg < 108 then
                    self.bg = COLORS[arg - 99].bright
                else
                    core.log("Unhandled formatting option: " .. arg)
                end
                core.log("Formatting Mode: " .. arg)
                i = i + 1
            end
        end,

        -- Query State
        ["n"] = function(args)
            self.proc:write(ESC .. self.cursor_row .. ";" .. self.cursor_col .. "R")
        end,
    }

    self.handler = {
        -- Basic ASCII
        ["[%g ]"] = function(char)
            self.buffer[self.cursor_col][self.cursor_row] = self:new_formatted_char(char)
            self.cursor_col = self.cursor_col + 1
            if self.cursor_col > self.columns then
                self.cursor_col = 1
                self.cursor_row = self.cursor_row + 1
            end
        end,
        ["\n"] = function()
            if self.cursor_row == self.scroll_region_end then
                for row = self.scroll_region_start + 1, self.scroll_region_end do
                    for col = 1, self.columns do
                        self.buffer[col][row - 1] = self.buffer[col][row]
                    end
                end
                for col = 1, self.columns do
                    self.buffer[col][self.scroll_region_end] = self:new_formatted_char(" ")
                end
            else
                self.cursor_row = self.cursor_row + 1
            end
        end,
        ["\b"] = function()
            self.cursor_col = self.cursor_col - 1
        end,
        ["\r"] = function()
            self.cursor_col = 1
        end,
        ["\a"] = function()
            core.log("BELL!")
        end,

        -- Simple Cursor Positioning
        [ESC .. "M"] = function()
            if self.cursor_row == self.scroll_region_start then
                for row = self.scroll_region_end, self.scroll_region_start + 1, -1 do
                    for col = 1, self.columns do
                        self.buffer[col][row] = self.buffer[col][row - 1]
                    end
                end
                for col = 1, self.columns do
                    self.buffer[col][self.scroll_region_start] = self:new_formatted_char(" ")
                end
            else
                self.cursor_row = self.cursor_row - 1
            end
        end,
        [ESC .. "7"] = function()
            self.saved_cursor.col = self.cursor_col
            self.saved_cursor.row = self.cursor_row
        end,
        [ESC .. "8"] = function()
            self.cursor_col = self.saved_cursor.col
            self.cursor_row = self.saved_cursor.row
        end,

        -- Enabling/Disabling stuff...
        [ESC .. "%[%?(%d+)h"] = function(option)
            option = tonumber(option)
            if option == 12 then
                self.blink_cursor = true
                self.last_blink = os.time()
            elseif option == 25 then
                self.cursor_visible = true
            else
                core.log("ENABLE: " .. option)
            end
        end,
        [ESC .. "%[%?(%d+)l"] = function(option)
            option = tonumber(option)
            if option == 12 then
                self.blink_cursor = false
                self.cursor_visible = true
            elseif option == 25 then
                self.blink_cursor = false
                self.cursor_visible = false
            else
                core.log("DISABLE: " .. option)
            end
        end,

        -- Operating System Command
        [ESC .. "%](%d+);([^\a]+)\a"] = function(command, str)
            if tonumber(command) == 0 then
                self.title = str
            else
                core.log("OSC " .. command .. ": " .. str)
            end
        end,

        -- Weird escape sequences that don't follow the normal pattern.
        [ESC .. "%(B"] = function()
            -- core.log("ASCII CHARACTER SET")
        end,
        [ESC .. "%[>(%d*)c"] = function(str)
            local n = tonumber(str, 10)
            if not n or n == 0 then
                self.proc:write(ESC .. "[0;0;0c")
            end
            core.log("TERMINAL MODE: " .. n)
        end,
        [ESC .. "[>=]"] = function()
            core.log("Please don't crash!")
        end,
    }

    self:display_string(CONNECT_MSG)
end

function TerminalView:delete_current_line(mode)
    local first = 1
    local last = self.columns
    if mode == 0 then
        first = self.cursor_col
    elseif mode == 1 then
        last = self.cursor_col
    end
    for i = first, last do
        self.buffer[i][self.cursor_row] = self:new_formatted_char(" ")
    end
end

function TerminalView:new_formatted_char(char)
    return {
        bg = self.bg,
        fg = self.fg,
        value = char,
    }
end

function TerminalView:try_close(...)
    self.proc:kill()
    self.log:close()
    TerminalView.super.try_close(self, ...)
end

function TerminalView:get_name()
    return self.title
end

local function sanitise(str)
    return str:gsub("%%", "%%%%")
end

function TerminalView:update(...)
    TerminalView.super.update(self, ...)
    local dest = self.visible and (self.old_y or core.root_view.size.y / 2) or 0
    self:move_towards(self.size, "y", dest)

    local output = ""
    local currently_alive = self.proc:running()
    if currently_alive then
        output = assert(self.proc:read_stdout())
    else
        if currently_alive ~= self.alive then
            self.alive = currently_alive
            output = string.format(TERMINATION_MSG, self.proc:returncode())
        end
    end

    if output:len() > 0 then
        self.log:write(output)
        self:display_string(output)
    end

    local now = system.get_time()
    if now > self.last_blink + self.blink_time and self.blink_cursor then
        self.cursor_visible = not self.cursor_visible
        self.last_blink = now
        core.redraw = true
    end
end

function TerminalView:on_text_input(text)
    self:input_string(text)
end

function TerminalView:input_string(str)
    self.proc:write(str)
end

function TerminalView:display_string(str)
    local i = 1
    local args

    local function eat(pattern)
        local first, last = str:find("^" .. pattern, i)
        local captures = { str:match("^" .. pattern, i) }
        if first == i then
            i = last + 1
            return table.unpack(captures)
        else
            return nil
        end
    end

    local function parse_arg()
        local arg = tonumber(eat("%d+", 10))
        if arg then
            args[#args + 1] = arg
            return true
        else
            return false
        end
    end

    while i <= str:len() do
        local found = false
        for pattern, func in pairs(self.handler) do
            local captures = { eat(pattern) }
            if captures[1] then
                func(table.unpack(captures))
                found = true
                break
            end
        end
        if not found and str:sub(i, i):byte() > 127 then
            i = i + 1
            core.log("UTF8")
            found = true
        end
        if not found and eat("\x1b%[") then
            found = true
            args = {}
            if parse_arg() then
                while eat(";") do
                    if not parse_arg() then
                        core.log("Escape sequence missing argument!")
                    end
                end
            end
            command = eat("%g")
            local handler = self.escape_handler[command]
            if handler then
                handler(args)
            else
                core.log("Missing handler for escape sequence " .. sanitise(command))
            end
        end
        if not found then
            core.log("ERROR: " .. sanitise(str:sub(i, str:len())))
            return
        end
    end
end

function TerminalView:draw()
    self:draw_background(style.background)

    local offx, offy = self:get_content_offset()
    local row_height = style.code_font:get_height()
    local col_width = style.code_font:get_width_subpixel(" ") / style.code_font:subpixel_scale()

    for row = 1, self.rows do
        for col = 1, self.columns do
            local cell = self.buffer[col][row]
            renderer.draw_rect(offx + (col - 1) * col_width, offy + (row - 1) * row_height, col_width + 1, row_height + 1, cell.bg)
        end
    end

    if self.cursor_visible then
        renderer.draw_rect(offx + (self.cursor_col - 1) * col_width, offy + row_height * (self.cursor_row - 1), col_width, row_height, style.caret);
    end

    for row = 1, self.rows do
        for col = 1, self.columns do
            local cell = self.buffer[col][row]
            common.draw_text(style.code_font, cell.fg, cell.value, "left", offx + (col - 1) * col_width, offy + (row - 0.5) * row_height, 0, 0)
        end
    end

end

local function predicate()
    return getmetatable(core.active_view) == TerminalView
end

-- this is a shared session used by terminal:view
-- it is not touched by "terminal:open-here"
local shared_view = nil
local function shared_view_exists()
    return shared_view and core.root_view.root_node:get_node_for_view(shared_view)
end
command.add(nil, {
    ["terminal:new"] = function()
        local node = core.root_view:get_active_node()
        if not shared_view_exists() then
            shared_view = TerminalView()
        end
        node:split(config.terminal.split_direction, shared_view)
        core.set_active_view(shared_view)
    end,
    ["terminal:toggle"] = function()
        if not shared_view_exists() then
            command.perform "terminal:new"
        else
            shared_view.visible = not shared_view.visible
            core.set_active_view(shared_view)
        end
    end,
    ["terminal:open-here"] = function()
        local node = core.root_view:get_active_node()
        node:add_view(TerminalView())
    end
})

command.add(predicate, {
    ["terminal:return"] = function()
        core.active_view:input_string("\r")
    end,
    ["terminal:up"] = function()
        core.active_view:input_string(ESC .. "OA")
    end,
    ["terminal:down"] = function()
        core.active_view:input_string(ESC .. "OB")
    end,
    ["terminal:right"] = function()
        core.active_view:input_string(ESC .. "OC")
    end,
    ["terminal:left"] = function()
        core.active_view:input_string(ESC .. "OD")
    end,
    ["terminal:backspace"] = function()
        core.active_view:input_string("\x7f")
    end,
    ["terminal:escape"] = function()
        core.active_view:input_string("\x1b")
    end,
    ["terminal:tab"] = function()
        core.active_view:input_string("\t")
    end,
})

keymap.add({
    ["return"] = "terminal:return",
    ["backspace"] = "terminal:backspace",
    ["up"] = "terminal:up",
    ["down"] = "terminal:down",
    ["left"] = "terminal:left",
    ["right"] = "terminal:right",
    ["escape"] = "terminal:escape",
    ["tab"] = "terminal:tab",

    ["ctrl+t"] = "terminal:new",
    ["ctrl+`"] = "terminal:toggle"
})
