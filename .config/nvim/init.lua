-- vim-plug setup
local Plug = vim.fn['plug#']
vim.call('plug#begin', '~/.config/nvim/plugged')
Plug 'nvim-tree/nvim-web-devicons'
Plug 'nvim-tree/nvim-tree.lua'
Plug 'junegunn/fzf'
Plug('junegunn/fzf', {dir = '~/.fzf', ['do'] = './install --all'})
Plug 'junegunn/fzf.vim'
Plug 'rking/ag.vim'
Plug 'scrooloose/nerdcommenter'
Plug 'neomake/neomake'
Plug 'vim-airline/vim-airline'
Plug 'Shougo/unite.vim'
Plug 'Quramy/vison'
Plug 'vim-syntastic/syntastic'
Plug 'airblade/vim-gitgutter'
Plug 'terryma/vim-multiple-cursors'
Plug 'tpope/vim-surround'
Plug 'maksimr/vim-jsbeautify'
Plug 'mcchrish/nnn.vim'
Plug('glacambre/firenvim', {['do'] = function() vim.fn['firenvim#install'](0) end})
Plug 'robitx/gp.nvim'
Plug 'mrcjkb/rustaceanvim'
Plug 'ishan9299/nvim-solarized-lua'
vim.call('plug#end')

-- Neovim specific settings
if vim.fn.has('nvim') == 1 then
  vim.api.nvim_create_autocmd('VimEnter', {
    pattern = '*',
    command = 'set wildmode=full'
  })
end

vim.cmd('syntax enable')
vim.cmd('filetype plugin indent on')

vim.o.scrolloff = 3
vim.o.compatible = false
vim.o.encoding = 'utf-8'
vim.o.fileencoding = 'utf-8'
vim.o.fileencodings = 'ucs-bom,utf8,prc'
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
vim.o.showmode = true
vim.o.list = true
vim.o.ruler = true
vim.o.backup = false
vim.o.writebackup = false
vim.o.swapfile = false

vim.opt.clipboard:append('unnamedplus')
vim.opt.statusline:append('%#warningmsg#')
vim.opt.statusline:append('%{SyntasticStatuslineFlag()}')
vim.opt.statusline:append('%*')
vim.opt.termguicolors = true

vim.g['airline#extensions#tabline#enabled'] = 1
vim.g.syntastic_always_populate_loc_list = 1
vim.g.syntastic_auto_loc_list = 1
vim.g.syntastic_check_on_open = 1
vim.g.syntastic_check_on_wq = 0
vim.g.syntastic_javascript_checkers = {'eslint'}
vim.g.syntastic_javascript_eslint_exec = 'eslint_d'
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.mapleader = ','

vim.keymap.set('', '<leader>b', vim.cmd.bnext)
vim.keymap.set('', '<leader>bb', vim.cmd.bprev)

-- Autocommands
vim.api.nvim_create_autocmd('InsertEnter', {
  pattern = '*',
  command = 'set number'
})

vim.api.nvim_create_autocmd('InsertLeave', {
  pattern = '*',
  command = 'set relativenumber'
})

vim.api.nvim_create_autocmd('StdinReadPre', {
  pattern = '*',
  command = 'let s:std_in=1'
})

require("nvim-tree").setup()

require("gp").setup({
  providers = {
    ollama = {
      disable = false
    },
    openai = {
      disable = true
    }
  }
})

--require('gen').setup({
  --model = 'llama3.1',
  --show_model = true,
  --display_mode = 'split',
  --debug = true
--})
