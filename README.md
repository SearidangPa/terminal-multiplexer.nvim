## terminal-multiplexer.nvim

Floating terminal multiplexer for Neovim. A tmux alternative for Windows (and anywhere else).

## Demo

https://github.com/user-attachments/assets/d4e23925-6d46-404a-b9ce-c732dd8dd7b2

## Install

```lua
-- lazy.nvim
{ "SearidangPa/terminal-multiplexer.nvim" }
```

## Setup

```lua
local TerminalMultiplexer = require("terminal-multiplexer")
local tm = TerminalMultiplexer.new({
  powershell = false, -- use pwsh.exe on Windows
})

vim.keymap.set("n", "<leader>t1", function() tm:toggle_float_terminal("main") end)
vim.keymap.set("n", "<leader>t2", function() tm:toggle_float_terminal("scratch") end)
vim.keymap.set("n", "<leader>ts", function() tm:search_terminal() end)
```

## API

| Method                           | Description                               |
| -------------------------------- | ----------------------------------------- |
| `tm:toggle_float_terminal(name)` | Show/hide a named floating terminal       |
| `tm:spawn(name)`                 | Create a terminal without showing it      |
| `tm:search_terminal()`           | Open a picker to switch between terminals |
| `tm:delete_terminal(name)`       | Remove a terminal and its buffers         |

## Terminal keybindings

These are set automatically inside every terminal buffer.

| Key      | Action            |
| -------- | ----------------- |
| `>`      | Next terminal     |
| `<`      | Previous terminal |
| `Ctrl+C` | Send interrupt    |
| `q`      | Hide terminal     |
