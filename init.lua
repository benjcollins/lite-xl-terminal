-- mod-version:2 -- lite-xl 2.0
local core = require "core"
local keymap = require "core.keymap"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local View = require "core.view"

local TerminalView = View:extend()

function TerminalView:new()
  TerminalView.super.new(self)
  self.scrollable = true

  self.proc = assert(process.start({ DATADIR .. "/plugins/terminal/terminal" }, {}))

  self.columns = 120
  self.rows = 100
  self.buffer = {}
  self.cursor_col = 0
  self.cursor_row = 0
  self.entry = ""

  for col = 0, self.columns do
    self.buffer[col] = {}
    for row = 0, self.rows do
      self.buffer[col][row] = " "
    end
  end
end

function TerminalView:try_close(...)
  TerminalView.super.try_close(self, ...)
end

function TerminalView:get_name()
  return "Terminal"
end

function TerminalView:update(...)
  TerminalView.super.update(self, ...)
  if not self.proc:running() then
    core.log("KILLED!")
  end
  local output = self.proc:read_stdout()
  if output then
    self:display_string(output)
  end
end

function TerminalView:on_text_input(text)
  self:input_string(text)
end

local function is_printable(char)
  local byte = string.byte(char)
  return byte >= 20 and byte <= 126
end

function TerminalView:input_string(str)
  -- for i = 1, string.len(str) do
  --   local char = string.sub(str, i, i)
  --   if char == "\n" then
  --     self.proc:write(self.entry .. "\n")
  --     self.entry = ""
  --   elseif char == "\b" then
  --     self.entry = self.entry:sub(0, self.entry:len()-1)
  --   elseif is_printable(char) then
  --     self.entry = self.entry .. char
  --   end
  --   self:display_string(char)
  -- end
  self.proc:write(str)
end

function TerminalView:display_string(str)
  local ESCAPE = string.char(27)
  for i = 1, string.len(str) do
    local char = str:sub(i, i)
    if char == "\n" then
      self.cursor_col = 0
      self.cursor_row = self.cursor_row + 1
    elseif char == "\b" then
      self.cursor_col = self.cursor_col - 1
      self:insert(" ")
    elseif char == ESCAPE then
      core.log("ESCAPE SEQUENCE!")
    elseif is_printable(char) then
      self:insert(char)
      self:advance_cursor()
    end
  end
end

function TerminalView:advance_cursor()
  self.cursor_col = self.cursor_col + 1
  if self.cursor_col >= self.columns then
    self.cursor_col = 0
    self.cursor_row = self.cursor_row + 1
  end
end

function TerminalView:insert(char)
  self.buffer[self.cursor_col][self.cursor_row] = char
end

function TerminalView:draw()
  self:draw_background(style.background)

  local offx, offy = self:get_content_offset()
  local row_height = style.code_font:get_height()
  local col_width = style.code_font:get_width_subpixel(" ") / style.code_font:subpixel_scale()

  for row = 0, self.rows do
    local line = ""
    for col = 0, self.columns do
      line = line .. self.buffer[col][row]
      if self.cursor_col == col and self.cursor_row == row then
        renderer.draw_rect(offx + col * col_width, offy + row_height * row, col_width, row_height, style.caret)
      end
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
  ["terminal:backspace"] = function()
    core.active_view:input_string("\b")
  end,
})

keymap.add({
  ["return"] = "terminal:return",
  ["backspace"] = "terminal:backspace",
  ["ctrl+t"] = "terminal:new",
})