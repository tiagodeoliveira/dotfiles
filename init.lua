-- vim-plug setup
local Plug = vim.fn['plug#']
vim.call('plug#begin', '~/.config/nvim/plugged')
Plug 'nvim-tree/nvim-web-devicons'
Plug 'nvim-tree/nvim-tree.lua'
Plug 'nvim-lualine/lualine.nvim'
Plug 'junegunn/fzf'
Plug('junegunn/fzf', {dir = '~/.fzf', ['do'] = './install --all'})
Plug 'junegunn/fzf.vim'
Plug 'scrooloose/nerdcommenter'
Plug 'neomake/neomake'
Plug 'airblade/vim-gitgutter'
Plug 'folke/tokyonight.nvim'
Plug '3rd/image.nvim'
Plug 'nvim-lua/plenary.nvim'
Plug 'RRethy/vim-illuminate'
Plug 'fei6409/log-highlight.nvim'
Plug 'neovim/nvim-lspconfig'
Plug('neoclide/coc.nvim', {branch='release'})
Plug 'drewipson/glowing-vim-markdown-preview'
Plug 'MeanderingProgrammer/render-markdown.nvim'
-- DAP (debugging)
Plug 'mfussenegger/nvim-dap'
Plug 'rcarriga/nvim-dap-ui'
Plug 'nvim-neotest/nvim-nio'          -- required by nvim-dap-ui
Plug 'mfussenegger/nvim-dap-python'   -- python adapter glue
Plug 'theHamsta/nvim-dap-virtual-text'-- show variable values inline
vim.call('plug#end')

-- coc.nvim runs on Node. Odd "Current" releases (e.g. 25) break coc-pyright with a
-- Web Storage localStorage error, so pin coc to Node 22 LTS explicitly -- a guard
-- that holds even if the global `node` later drifts to a non-LTS release. Resolve
-- via mise so it works regardless of home dir, mise data location, or patch version.
-- Must be set before coc starts its language servers.
local node22 = vim.trim(vim.fn.system({ 'mise', 'where', 'node@22' }))
if vim.v.shell_error == 0 and node22 ~= '' then
  vim.g.coc_node_path = node22 .. '/bin/node'
end

if vim.fn.has('nvim') == 1 then
  vim.api.nvim_create_autocmd('VimEnter', {
    pattern = '*',
    command = 'set wildmode=full'
  })
end

vim.cmd('syntax enable')
vim.cmd('filetype plugin indent on')

vim.o.autoread = true
vim.o.updatetime = 300
vim.o.scrolloff = 3
vim.o.encoding = 'utf-8'
vim.o.fileencoding = 'utf-8'
vim.o.showcmd = true
vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.expandtab = true
vim.o.backspace = 'indent,eol,start'
vim.o.autoindent = true
vim.o.number = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.incsearch = true
vim.o.hlsearch = true
vim.o.showmatch = true
vim.o.list = true
vim.o.backup = false
vim.o.writebackup = false
vim.o.swapfile = false

vim.opt.clipboard:append('unnamedplus')
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.mapleader = ','

-- buffer navigation 
-- -- next and previous
vim.keymap.set('', '<leader>b', vim.cmd.bnext)
vim.keymap.set('', '<leader>bb', vim.cmd.bprev)
-- -- leader 1,2,3...
vim.keymap.set('n', '<leader>1', ':b1<CR>')
vim.keymap.set('n', '<leader>2', ':b2<CR>')
vim.keymap.set('n', '<leader>3', ':b3<CR>')
vim.keymap.set('n', '<leader>4', ':b4<CR>')
vim.keymap.set('n', '<leader>5', ':b5<CR>')
vim.keymap.set('n', '<leader>6', ':b6<CR>')
vim.keymap.set('n', '<leader>7', ':b7<CR>')
vim.keymap.set('n', '<leader>8', ':b8<CR>')
vim.keymap.set('n', '<leader>9', ':b9<CR>')
-- -- close buffer
vim.keymap.set('', '<leader>q', ':bd<CR>')

-- FZF shortcuts
vim.keymap.set('n', '<leader>f', ':Files<CR>')
vim.keymap.set('n', '<leader>g', ':GFiles<CR>')
vim.keymap.set('n', '<leader>r', ':Rg<CR>')
vim.keymap.set('n', '<leader>l', ':BLines<CR>')
vim.keymap.set('n', '<leader>h', ':History<CR>')
vim.keymap.set('n', '<leader>a', ':Files -a<CR>')  -- Show all files including hidden

vim.keymap.set('n', '<leader>-', ':NvimTreeResize -10<CR>')
vim.keymap.set('n', '<leader>+', ':NvimTreeResize +10<CR>')

vim.keymap.set('n', '<F1>', '<nop>', { noremap = true})
vim.keymap.set('i', '<F1>', '<nop>', { noremap = true})

vim.keymap.set('v', '>', '>gv')
vim.keymap.set('v', '<', '<gv')

-- Option+Arrow word jumping (insert and normal mode)
vim.keymap.set({'i', 'n'}, '<M-Left>', '<C-Left>', { noremap = true })
vim.keymap.set({'i', 'n'}, '<M-Right>', '<C-Right>', { noremap = true })

vim.keymap.set('i', '<CR>', function()
  if vim.fn['coc#pum#visible']() == 1 then
    return vim.fn['coc#pum#confirm']()
  else
    return vim.api.nvim_replace_termcodes('<CR>', true, false, true)
  end
end, { expr = true, noremap = true })

-- FZF configuration to show hidden files by default
vim.cmd([[
  let $FZF_DEFAULT_COMMAND = 'find . -type f -not -path "*/\.git/*"'
]])

-- Autocommands
vim.api.nvim_create_autocmd('InsertEnter', {
  pattern = '*',
  command = 'set number'
})

vim.api.nvim_create_autocmd('StdinReadPre', {
  pattern = '*',
  command = 'let s:std_in=1'
})

require("nvim-tree").setup({
  view = {
    width = 30,
  },
  filters = {
    dotfiles = false,  -- Show dotfiles (hidden files)
    custom = {},       -- Don't filter any files
  },
  git = {
    ignore = false,    -- Show files in .gitignore
  },
  renderer = {
    root_folder_label = ":t:s?$?/?",
    highlight_git = "icon",
    highlight_opened_files = "name",
  },
})

vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "CursorHoldI", "FocusGained" }, {
  command = "if mode() != 'c' | checktime | endif",
  pattern = { "*" },
})

require("tokyonight").setup({
  transparent = true
})

-- Set colorscheme after plugins load
vim.cmd('colorscheme tokyonight')

vim.o.title = true
-- getcwd(): project path; fnamemodify(..., ':t') = last path component (project dir)
vim.o.titlestring = "nvim - %{fnamemodify(getcwd(), ':t')} · %t"

-- Image.nvim configuration
require("image").setup({
  backend = "kitty",  -- or "ueberzug" 
  integrations = {
    markdown = {
      enabled = true,
      clear_in_insert_mode = false,
      download_remote_images = true,
      only_render_image_at_cursor = false,
      filetypes = { "markdown", "vimwiki" },
    },
    neorg = {
      enabled = true,
      clear_in_insert_mode = false,
      download_remote_images = true,
      only_render_image_at_cursor = false,
      filetypes = { "norg" },
    },
  },
  max_width = nil,
  max_height = nil,
  max_width_window_percentage = nil,
  max_height_window_percentage = 50,
  window_overlap_clear_enabled = false,
  window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
  editor_only_render_when_focused = false,
  tmux_show_only_in_active_window = false,
  hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp" },
})

require('lualine').setup({
  tabline = {
    lualine_a = {'buffers'},
    lualine_z = {'tabs'}
  }
})

-- ============================================================================
-- DAP: line-by-line debugging (python via debugpy)
-- ============================================================================
local dap = require('dap')
local dapui = require('dapui')

-- Point dap-python at the active python3 on PATH (mise-managed). It must have
-- debugpy + your project deps installed; setup.sh provisions the global one.
local python3 = vim.fn.exepath('python3')
require('dap-python').setup(python3 ~= '' and python3 or 'python3')

dapui.setup()
require('nvim-dap-virtual-text').setup()

-- Auto open/close the UI panes when a session starts/ends
dap.listeners.before.attach.dapui_config       = function() dapui.open() end
dap.listeners.before.launch.dapui_config        = function() dapui.open() end
dap.listeners.before.event_terminated.dapui_config = function() dapui.close() end
dap.listeners.before.event_exited.dapui_config     = function() dapui.close() end

-- Breakpoint sign in the gutter
vim.fn.sign_define('DapBreakpoint', { text = '●', texthl = 'DiagnosticError', linehl = '', numhl = '' })

-- Keymaps: F-keys for stepping, <leader>d* for the rest
vim.keymap.set('n', '<F5>',  dap.continue,          { desc = 'DAP continue/start' })
vim.keymap.set('n', '<F10>', dap.step_over,         { desc = 'DAP step over' })
vim.keymap.set('n', '<F11>', dap.step_into,         { desc = 'DAP step into' })
vim.keymap.set('n', '<F12>', dap.step_out,          { desc = 'DAP step out' })
vim.keymap.set('n', '<leader>db', dap.toggle_breakpoint, { desc = 'DAP toggle breakpoint' })
vim.keymap.set('n', '<leader>dB', function()
  dap.set_breakpoint(vim.fn.input('Breakpoint condition: '))
end, { desc = 'DAP conditional breakpoint' })
vim.keymap.set('n', '<leader>dr', dap.repl.open,    { desc = 'DAP open REPL' })
vim.keymap.set('n', '<leader>du', dapui.toggle,     { desc = 'DAP toggle UI' })
vim.keymap.set('n', '<leader>dt', dap.terminate,    { desc = 'DAP terminate' })
-- Eval: word under cursor (normal) or visual selection -> floating value.
-- Press the same key again to jump INTO the float and expand nested values.
vim.keymap.set({ 'n', 'v' }, '<leader>de', function() dapui.eval() end, { desc = 'DAP eval expression' })

-- ============================================================================
-- KEYMAP CHEAT-SHEET  (leader = ",")  -- keep in sync when you add mappings
-- ============================================================================
--
-- BUFFERS
--   ,b            next buffer            ,bb           previous buffer
--   ,1 .. ,9      jump to buffer 1..9    ,q            close buffer
--
-- FILES / SEARCH (fzf)
--   ,f            Files                  ,g            Git files
--   ,r            Rg (grep in project)   ,l            BLines (lines in buffer)
--   ,h            History                ,a            Files incl. hidden
--
-- NVIM-TREE
--   ,-            shrink tree (-10)      ,+            widen tree (+10)
--
-- EDITING
--   > / <  (visual) reindent, keep selection
--   M-Left / M-Right   jump word left/right (insert & normal)
--   <CR>   (insert)    confirm coc completion if popup is open
--   <F1>               disabled (no-op)
--
-- DEBUG (nvim-dap)  -- panes: <C-w>h/j/k/l to move between them
--   <F5>          continue / start       ,db           toggle breakpoint
--   <F10>         step over              ,dB           conditional breakpoint
--   <F11>         step into              ,dr           open REPL
--   <F12>         step out               ,du           toggle DAP UI
--   ,dt           terminate              ,de           eval (cursor / visual)
--   in UI panes:  i = add watch   <CR> = expand   e = edit   d = remove
-- ============================================================================

