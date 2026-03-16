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
Plug 'glowing-vim-markdown-preview'
Plug 'MeanderingProgrammer/render-markdown.nvim'
vim.call('plug#end')

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

