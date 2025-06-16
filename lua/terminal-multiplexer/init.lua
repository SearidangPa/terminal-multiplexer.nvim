---@class TerminalMultiplexer
---@field all_terminals table<string, TerminalMultiplexer.FloatTermState>
---@field terminal_order string[]
---@field last_terminal_name string?
---@field powershell boolean
---@field augroup number
---@field ns_id number
---@field toggle_float_terminal fun(self: TerminalMultiplexer, terminal_name: string): TerminalMultiplexer.FloatTermState
---@field search_terminal fun(self: TerminalMultiplexer): nil
---@field create_float_window fun(self: TerminalMultiplexer, float_terminal_state: TerminalMultiplexer.FloatTermState, terminal_name: string): nil
---@field delete_terminal fun(self: TerminalMultiplexer, terminal_name: string): nil
local TerminalMultiplexer = {}
TerminalMultiplexer.__index = TerminalMultiplexer

---@class TerminalMultiplexer.FloatTermState
---@field bufnr number
---@field win number
---@field footer_buf number
---@field footer_win number
---@field chan number

---@class TerminalMultiplexer.Options
---@field powershell? boolean

---@param opts TerminalMultiplexer.Options
---@return TerminalMultiplexer
function TerminalMultiplexer.new(opts)
  vim.cmd [[highlight TerminalNameUnderline gui=underline]]
  opts = opts or {}
  local self = setmetatable({}, TerminalMultiplexer)
  self.all_terminals = {} --- @type table<string, TerminalMultiplexer.FloatTermState>
  self.terminal_order = {} --- @type string[]
  self.last_terminal_name = nil
  self.powershell = opts.powershell or false
  self.augroup = vim.api.nvim_create_augroup('TerminalMultiplexer', { clear = true }) --- @type number
  self.ns_id = vim.api.nvim_create_namespace 'TerminalMultiplexer'
  return self
end

---@param terminal_name string
function TerminalMultiplexer:delete_terminal(terminal_name)
  local float_terminal = self.all_terminals[terminal_name]
  if not float_terminal then
    return
  end

  if vim.api.nvim_buf_is_valid(float_terminal.bufnr) then
    vim.api.nvim_buf_delete(float_terminal.bufnr, { force = true })
  end
  if vim.api.nvim_buf_is_valid(float_terminal.footer_buf) then
    vim.api.nvim_buf_delete(float_terminal.footer_buf, { force = true })
  end
  self.all_terminals[terminal_name] = nil

  for i, name in ipairs(self.terminal_order) do
    if name == terminal_name then
      table.remove(self.terminal_order, i)
      break
    end
  end
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

  local handle_choice = function(terminal_name)
    if not terminal_name then
      vim.notify('No terminal selected', vim.log.levels.INFO)
      return
    end
    self:toggle_float_terminal(terminal_name)
  end

  vim.ui.select(all_terminal_names, opts, function(choice) handle_choice(choice) end)
end

---@param terminal_name string
---@return TerminalMultiplexer.FloatTermState
function TerminalMultiplexer:toggle_float_terminal(terminal_name)
  assert(terminal_name, 'Terminal name is required')
  local self_ref = self

  local current_float_term_state = self_ref.all_terminals[terminal_name]
  if not current_float_term_state then
    current_float_term_state = {
      bufnr = -1,
      win = -1,
      chan = 0,
      footer_buf = -1,
      footer_win = -1,
    }
    self_ref.all_terminals[terminal_name] = current_float_term_state
  end

  if not vim.tbl_contains(self_ref.terminal_order, terminal_name) then
    table.insert(self_ref.terminal_order, terminal_name)
  end

  local is_visible = vim.api.nvim_win_is_valid(current_float_term_state.win)

  if is_visible then
    vim.api.nvim_win_hide(current_float_term_state.win)
    vim.api.nvim_win_hide(current_float_term_state.footer_win)
    return self_ref.all_terminals[terminal_name]
  end

  self_ref:_create_float_window(current_float_term_state, terminal_name)
  if vim.bo[current_float_term_state.bufnr].buftype ~= 'terminal' then
    if vim.fn.has 'win32' == 1 and self_ref.powershell then
      vim.cmd.term [["C:\Program Files\PowerShell\7\pwsh.exe"]]
    else
      vim.cmd.term()
    end
    vim.schedule(function() vim.cmd [[stopinsert]] end)
    current_float_term_state.chan = vim.bo.channel
  end

  self_ref:_set_up_buffer_keybind(current_float_term_state)
  self_ref.last_terminal_name = terminal_name
  return self_ref.all_terminals[terminal_name]
end

--- === Private functions ===

function TerminalMultiplexer:_set_up_buffer_keybind(current_float_term_state)
  local self_ref = self

  local map_opts = { noremap = true, silent = true, buffer = current_float_term_state.bufnr }
  local next_term = function() self_ref:_navigate_terminal(1) end
  local prev_term = function() self_ref:_navigate_terminal(-1) end

  vim.keymap.set('n', '>', next_term, map_opts)
  vim.keymap.set('n', '<', prev_term, map_opts)

  local function send_ctrl_c() vim.api.nvim_chan_send(current_float_term_state.chan, '\x03') end

  local function hide_terminal()
    if vim.api.nvim_win_is_valid(current_float_term_state.footer_win) then
      vim.api.nvim_win_hide(current_float_term_state.footer_win)
    end
    if vim.api.nvim_win_is_valid(current_float_term_state.win) then
      vim.api.nvim_win_hide(current_float_term_state.win)
    end
  end

  vim.keymap.set('n', '<C-c>', send_ctrl_c, map_opts)
  vim.keymap.set('n', 'q', hide_terminal, map_opts)

  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufHidden' }, {
    group = self.augroup,
    buffer = current_float_term_state.bufnr,
    callback = function()
      if vim.api.nvim_buf_is_valid(current_float_term_state.footer_buf) then
        vim.api.nvim_buf_delete(current_float_term_state.footer_buf, { force = true })
      end
    end,
  })
end

---@param direction number
function TerminalMultiplexer:_navigate_terminal(direction)
  local self_ref = self
  if #self_ref.terminal_order == 0 then
    vim.notify('No terminals available', vim.log.levels.INFO)
    return
  end

  local current_buf = vim.api.nvim_get_current_buf()
  local current_terminal_name = nil

  for terminal_name, state in pairs(self_ref.all_terminals) do
    if state.bufnr == current_buf then
      current_terminal_name = terminal_name
      break
    end
  end

  if not current_terminal_name then
    self_ref:toggle_float_terminal(self_ref.terminal_order[1])
    return
  end

  local current_index = nil
  for i, name in ipairs(self_ref.terminal_order) do
    if name == current_terminal_name then
      current_index = i
      break
    end
  end

  if not current_index then
    vim.notify('Current terminal not found in order list', vim.log.levels.ERROR)
    return
  end

  local next_index = ((current_index - 1 + direction) % #self_ref.terminal_order) + 1
  local next_terminal_name = self_ref.terminal_order[next_index]

  self_ref:toggle_float_terminal(next_terminal_name)

  -- Hide current terminal
  vim.defer_fn(function()
    local current_term_state = self_ref.all_terminals[current_terminal_name]
    if vim.api.nvim_win_is_valid(current_term_state.win) then
      vim.api.nvim_win_hide(current_term_state.win)
      vim.api.nvim_win_hide(current_term_state.footer_win)
    end
  end, 25)
end

---@param float_terminal_state TerminalMultiplexer.FloatTermState
---@param terminal_name string
function TerminalMultiplexer:_create_float_window(float_terminal_state, terminal_name)
  local width = math.floor(vim.o.columns)
  local height = math.floor(vim.o.lines)
  local row = math.floor((vim.o.columns - width))
  local col = math.floor((vim.o.lines - height))

  if float_terminal_state.bufnr == -1 then
    float_terminal_state.bufnr = vim.api.nvim_create_buf(false, true)
  end
  float_terminal_state.footer_buf = vim.api.nvim_create_buf(false, true)

  local padding = string.rep(' ', width - #terminal_name - 1)
  local footer_text = padding .. terminal_name
  vim.api.nvim_buf_set_lines(float_terminal_state.footer_buf, 0, -1, false, { footer_text })

  vim.api.nvim_buf_set_extmark(float_terminal_state.footer_buf, self.ns_id, 0, 0, {
    end_row = 0,
    end_col = #footer_text,
    hl_group = 'Title',
  })

  vim.api.nvim_buf_set_extmark(float_terminal_state.footer_buf, self.ns_id, 0, #padding, {
    end_row = 0,
    end_col = #footer_text,
    hl_group = 'TerminalNameUnderline',
  })

  float_terminal_state.win = vim.api.nvim_open_win(float_terminal_state.bufnr, true, {
    relative = 'editor',
    width = width,
    height = height - 2,
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
    row = height - 2,
    col = 0,
    style = 'minimal',
    border = 'none',
  })
end

return TerminalMultiplexer
