-- mod-version:2 -- lite-xl 2.0
local core = require "core"
local keymap = require "core.keymap"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local View = require "core.view"

local TerminalView = View:extend()

local ESC = "\x1b"

function TerminalView:new()
    TerminalView.super.new(self)
    self.scrollable = true

    self.proc = assert(process.start({ DATADIR .. "/plugins/terminal/terminal" }, {}))

    self.columns = 80
    self.rows = 24
    self.buffer = {}
    self.cursor_col = 0
    self.cursor_row = 0
    self.last_blink = os.time()
    self.cursor_visible = true
    self.blink_cursor = true

    for col = 0, self.columns do
        self.buffer[col] = {}
        for row = 0, self.rows do
            self.buffer[col][row] = " "
        end
    end

    self.escape_handler = {

        -- Cursor Positioning
        ["A"] = function(args)
            self.cursor_row = self.cursor_row - (args[0] or 1)
        end,
        ["B"] = function(args)
            self.cursor_row = self.cursor_row + (args[0] or 1)
        end,
        ["C"] = function(args)
            self.cursor_col = self.cursor_col + (args[0] or 1)
        end,
        ["D"] = function(args)
            self.cursor_col = self.cursor_col - (args[0] or 1)
        end,

        -- Text Modification
        ["K"] = function(args)
            local mode = args[0] or 0
            if mode == 0 then
                for i = self.cursor_col, self.columns do
                    self.buffer[i][self.cursor_row] = " "
                end
            else
                core.log("TODO! " .. mode)
            end
        end,
        ["@"] = function(args)
            local count = args[0] or 1
            for i = self.columns, self.cursor_col + count, -1 do
                self.buffer[i][self.cursor_row] = self.buffer[i - count][self.cursor_row]
            end
            for i = self.cursor_col, self.cursor_col + count - 1 do
                self.buffer[i][self.cursor_row] = " "
            end
        end,
        ["P"] = function(args)
            local count = args[0] or 1
            for i = self.cursor_col + count, self.columns do
                self.buffer[i - count][self.cursor_row] = self.buffer[i][self.cursor_row]
            end
            for i = self.columns - count, self.columns do
                self.buffer[i][self.cursor_row] = " "
            end
        end,
    }

    self.handler = {
        -- Basic ASCII
        ["[%g ]"] = function(char)
            self.buffer[self.cursor_col][self.cursor_row] = char
            self.cursor_col = self.cursor_col + 1
        end,
        ["\n"] = function()
            self.cursor_row = self.cursor_row + 1
        end,
        ["\b"] = function()
            self.cursor_col = self.cursor_col - 1
        end,
        ["\r"] = function()
            self.cursor_col = 0
        end,
        ["\a"] = function()
            core.log("BELL!")
        end,

        -- Weird escape sequences that don't follow the normal pattern.
        [ESC .. "%[%?12h"] = function()
            self:enable_blinking()
        end,
        [ESC .. "%[%?12l"] = function()
            self:disable_blinking()
        end,
        [ESC .. "%[%?25h"] = function()
            self:show_cursor()
        end,
        [ESC .. "%[%?25l"] = function()
            self:hide_cursor()
        end,
    }
end

function TerminalView:enable_blinking()
    self.blink_cursor = true
    self.last_blink = os.time()
end

function TerminalView:disable_blinking()
    self.blink_cursor = false
    self.cursor_visible = true
end

function TerminalView:show_cursor()
    self.blink_cursor = false
    self.cursor_visible = true
end

function TerminalView:hide_cursor()
    self.blink_cursor = false
    self.cursor_visible = false
end

function TerminalView:try_close(...)
    self.proc:kill()
    TerminalView.super.try_close(self, ...)
end

function TerminalView:get_name()
    return "Terminal"
end

function TerminalView:update(...)
    TerminalView.super.update(self, ...)
    local output = self.proc:read_stdout()
    if output then
        self:display_string(output)
    end

    local now = os.time()
    if now > self.last_blink and self.blink_cursor then
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
    local args = {}
    local arg_i = 0

    local function eat(pattern)
        local first, last = str:find(pattern, i)
        if first == i then
            i = last + 1
            return str:sub(first, last)
        else
            return nil
        end
    end

    local function parse_arg()
        local arg = tonumber(eat("%d*", 10))
        if arg then
            args[arg_i] = arg
            arg_i = arg_i + 1
            return true
        else
            return false
        end
    end

    while i <= str:len() do
        local found = false
        for pattern, func in pairs(self.handler) do
            local match = eat(pattern)
            if match then
                func(match)
                found = true
                break
            end
        end
        if not found and eat("\x1b%[") then
            found = true
            args = {}
            arg_i = 0
            if parse_arg() then
                while eat(";") do
                    if not parse_arg() then
                        core.log("Escape sequence missing argument!")
                    end
                end
            end
            command = eat("%g")
            core.log(command .. " " .. (args[0] or 1))
            local handler = self.escape_handler[command]
            if handler then
                handler(args)
            else
                core.log("Missing handler for escape sequence " .. command)
            end
        end
        if not found then
            core.log("ERROR: " .. string.byte(str, i, i) .. ", " .. str:sub(i, str:len()))
            return
        end
    end
end

function TerminalView:draw()
    self:draw_background(style.background)

    local offx, offy = self:get_content_offset()
    local row_height = style.code_font:get_height()
    local col_width = style.code_font:get_width_subpixel(" ") / style.code_font:subpixel_scale()

    renderer.draw_rect(offx + self.cursor_col * col_width, offy + row_height * self.cursor_row, col_width, row_height, style.caret);
    if not self.cursor_visible then
        renderer.draw_rect(offx + self.cursor_col * col_width + 1, offy + row_height * self.cursor_row + 1, col_width - 2, row_height - 2, style.background)
    end

    for row = 0, self.rows do
        local line = ""
        for col = 0, self.columns do
            line = line .. self.buffer[col][row]
        end
        common.draw_text(style.code_font, style.text, line, "left", offx, offy + (row + 0.5) * row_height, 0, 0)
    end

end

local function predicate()
    return getmetatable(core.active_view) == TerminalView
end

command.add(nil, {
    ["terminal:new"] = function()
        local node = core.root_view:get_active_node()
        node:add_view(TerminalView())
    end
})

command.add(predicate, {
    ["terminal:return"] = function()
        core.active_view:input_string("\n")
    end,
    ["terminal:up"] = function()
        core.active_view:input_string(ESC .. "OA")
    end,
    ["terminal:down"] = function()
        core.active_view:input_string(ESC .. "OB")
    end,
    ["terminal:left"] = function()
        core.active_view:input_string(ESC .. "OC")
    end,
    ["terminal:right"] = function()
        core.active_view:input_string(ESC .. "OD")
    end,
    ["terminal:backspace"] = function()
        core.active_view:input_string("\b")
    end,
})

keymap.add({
    ["return"] = "terminal:return",
    ["backspace"] = "terminal:backspace",
    ["up"] = "terminal:up",
    ["down"] = "terminal:down",
    ["left"] = "terminal:left",
    ["right"] = "terminal:right",

    ["ctrl+t"] = "terminal:new",
})