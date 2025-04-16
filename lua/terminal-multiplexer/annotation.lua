---@class TerminalMultiplexer
---@field all_terminals table<string, Float_Term_State> Dictionary of all terminals by name
---@field terminal_order string[] Order of terminal creation
---@field last_terminal_name string|nil Name of the last accessed terminal
---@field augroup number Vim autogroup ID
---@field toggle_float_terminal fun(self: TerminalMultiplexer, terminal_name: string): Float_Term_State
---@field create_float_window fun(self: TerminalMultiplexer, float_terminal_state: Float_Term_State, terminal_name: string): nil
---@field delete_terminal fun(self: TerminalMultiplexer, terminal_name: string): nil

---@class Float_Term_State
---@field buf number Buffer ID
---@field win number Window ID
---@field footer_buf number Footer buffer ID
---@field footer_win number Footer window ID
---@field chan number
---@field status string Status of the terminal (e.g., 'running', 'passed', 'failed')

---@class TerminalMultiplexer.Options
---@field powershell? boolean
