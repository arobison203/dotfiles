inoremap kj <Esc>
nnoremap x "_x
set number
set termguicolors
syntax on
colorscheme catppuccin
set clipboard=unnamedplus
let &t_SI.="\e[5 q" "SI = INSERT mode
let &t_SR.="\e[4 q" "SR = REPLACE mode
let &t_EI.="\e[1 q" "EI = NORMAL mode (ELSE)
