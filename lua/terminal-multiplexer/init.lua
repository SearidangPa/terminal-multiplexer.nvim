local TerminalMultiplexer = {}
TerminalMultiplexer.__index = TerminalMultiplexer
vim.cmd [[highlight TerminalNameUnderline gui=underline]]

---@param opts TerminalMultiplexer.Options
---@return TerminalMultiplexer
function TerminalMultiplexer.new(opts)
  opts = opts or {}
  local self = setmetatable({}, TerminalMultiplexer)
  self.all_terminals = {} --- @type table<string, Float_Term_State>
  self.terminal_order = {} --- @type string[]
  self.last_terminal_name = nil
  self.powershell = opts.powershell or false
  self.augroup = vim.api.nvim_create_augroup('TerminalMultiplexer', { clear = true }) --- @type number
  return self
end

function TerminalMultiplexer:search_terminal()
  local opts = {
    prompt = 'Select terminal:',
    format_item = function(item) return item end,
  }

  local all_terminal_names = {} --- @type string[]
  for test_name, _ in pairs(self.all_terminals) do
    table.insert(all_terminal_names, test_name)
  end

  local handle_choice = function(choice)
    if not choice then
      return
    end
    local terminal_name = choice:match '[\t%s][^\t%s]+[\t%s]+(.+)$'
    self:toggle_float_terminal(terminal_name)
  end

  vim.ui.select(all_terminal_names, opts, function(choice) handle_choice(choice) end)
end

---@param terminal_name string
---@return Float_Term_State
function TerminalMultiplexer:toggle_float_terminal(terminal_name)
  assert(terminal_name, 'Terminal name is required')

  local current_float_term_state = self.all_terminals[terminal_name]
  if not current_float_term_state then
    current_float_term_state = {
      buf = -1,
      win = -1,
      chan = 0,
      footer_buf = -1,
      footer_win = -1,
    }
    self.all_terminals[terminal_name] = current_float_term_state
  end

  if not vim.tbl_contains(self.terminal_order, terminal_name) then
    table.insert(self.terminal_order, terminal_name)
  end

  local is_visible = vim.api.nvim_win_is_valid(current_float_term_state.win)

  if is_visible then
    vim.api.nvim_win_hide(current_float_term_state.win)
    vim.api.nvim_win_hide(current_float_term_state.footer_win)
    return self.all_terminals[terminal_name]
  end

  self:_create_float_window(current_float_term_state, terminal_name)
  if vim.bo[current_float_term_state.buf].buftype ~= 'terminal' then
    if vim.fn.has 'win32' == 1 then
      if self.powershell then
        vim.cmd.term 'powershell.exe'
      else
        vim.cmd.term 'cmd.exe'
      end
    else
      vim.cmd.term()
    end
    current_float_term_state.chan = vim.bo.channel
  end

  self:_set_up_buffer_keybind(current_float_term_state)
  self.last_terminal_name = terminal_name
  return self.all_terminals[terminal_name]
end

---@param terminal_name string Name of the terminal to delete
function TerminalMultiplexer:delete_terminal(terminal_name)
  local float_terminal = self.all_terminals[terminal_name]
  if not float_terminal then
    return
  end

  vim.api.nvim_buf_delete(float_terminal.buf, { force = true })
  vim.api.nvim_buf_delete(float_terminal.footer_buf, { force = true })
  self.all_terminals[terminal_name] = nil

  for i, name in ipairs(self.terminal_order) do
    if name == terminal_name then
      table.remove(self.terminal_order, i)
      break
    end
  end
end

--- === Private functions ===

function TerminalMultiplexer:_set_up_buffer_keybind(current_float_term_state)
  local map_opts = { noremap = true, silent = true, buffer = current_float_term_state.buf }
  local next_term = function() self:navigate_terminal(1) end
  local prev_term = function() self:navigate_terminal(-1) end

  vim.keymap.set('n', '>', next_term, map_opts)
  vim.keymap.set('n', '<', prev_term, map_opts)

  local close_term = function()
    if vim.api.nvim_win_is_valid(current_float_term_state.footer_win) then
      vim.api.nvim_win_hide(current_float_term_state.footer_win)
    end
    if vim.api.nvim_win_is_valid(current_float_term_state.win) then
      vim.api.nvim_win_hide(current_float_term_state.win)
    end
  end
  vim.keymap.set('n', 'q', close_term, map_opts)
end

---@param direction number 1 for next, -1 for previous
function TerminalMultiplexer:_navigate_terminal(direction)
  if #self.terminal_order == 0 then
    vim.notify('No terminals available', vim.log.levels.INFO)
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local current_terminal_name = nil

  for terminal_name, state in pairs(self.all_terminals) do
    if state.buf == current_buf then
      current_terminal_name = terminal_name
      break
    end
  end

  if not current_terminal_name then
    self:toggle_float_terminal(self.terminal_order[1])
    return
  end

  local current_index = nil
  for i, name in ipairs(self.terminal_order) do
    if name == current_terminal_name then
      current_index = i
      break
    end
  end

  if not current_index then
    vim.notify('Current terminal not found in order list', vim.log.levels.ERROR)
    return
  end

  local next_index = ((current_index - 1 + direction) % #self.terminal_order) + 1
  local next_terminal_name = self.terminal_order[next_index]

  local current_term_state = self.all_terminals[current_terminal_name]
  if vim.api.nvim_win_is_valid(current_term_state.win) then
    vim.api.nvim_win_hide(current_term_state.win)
    vim.api.nvim_win_hide(current_term_state.footer_win)
  end

  self:toggle_float_terminal(next_terminal_name)
end

---@param float_terminal_state Float_Term_State
---@param terminal_name string
function TerminalMultiplexer:_create_float_window(float_terminal_state, terminal_name)
  local width = math.floor(vim.o.columns)
  local height = math.floor(vim.o.lines)
  local row = math.floor((vim.o.columns - width))
  local col = math.floor((vim.o.lines - height))

  if float_terminal_state.buf == -1 then
    float_terminal_state.buf = vim.api.nvim_create_buf(false, true)
  end
  float_terminal_state.footer_buf = vim.api.nvim_create_buf(false, true)

  local padding = string.rep(' ', width - #terminal_name - 1)
  local footer_text = padding .. terminal_name
  vim.api.nvim_buf_set_lines(float_terminal_state.footer_buf, 0, -1, false, { footer_text })
  ---@diagnostic disable-next-line: deprecated
  vim.api.nvim_buf_add_highlight(float_terminal_state.footer_buf, -1, 'Title', 0, 0, -1)
  ---@diagnostic disable-next-line: deprecated
  vim.api.nvim_buf_add_highlight(float_terminal_state.footer_buf, -1, 'TerminalNameUnderline', 0, #padding, -1)

  float_terminal_state.win = vim.api.nvim_open_win(float_terminal_state.buf, true, {
    relative = 'editor',
    width = width,
    height = height - 3,
    row = row,
    col = col,
    style = 'minimal',
    border = 'none',
  })

  vim.api.nvim_win_call(float_terminal_state.win, function() vim.cmd 'normal! G' end)
  float_terminal_state.footer_win = vim.api.nvim_open_win(float_terminal_state.footer_buf, false, {
    relative = 'win',
    width = width,
    height = 1,
    row = height - 3,
    col = 0,
    style = 'minimal',
    border = 'none',
  })
end

vim.api.nvim_create_autocmd('TermOpen', {
  group = vim.api.nvim_create_augroup('custom-term-open', { clear = true }),
  callback = function()
    vim.opt.number = false
    vim.opt.relativenumber = false
  end,
})

return TerminalMultiplexer
