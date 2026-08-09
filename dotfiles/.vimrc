call plug#begin('~/.vim/plugged')

Plug 'tpope/vim-sensible'
Plug 'preservim/nerdtree'
Plug 'vim-airline/vim-airline'
Plug 'neoclide/coc.nvim', {'branch': 'release'}
call plug#end()

" 基本设置
set number
set cursorline

" 调整 coc.nvim 自动补全菜单的颜色
" Pmenu 是菜单背景和文字，PmenuSel 是当前选中项的颜色

" 1. 正常的菜单项：深灰色背景（#2a2a2a），灰色文字（#d0d0d0）
highlight CocPum          guibg=#2a2a2a guifg=#d0d0d0 ctermbg=235 ctermfg=252
highlight Pmenu           guibg=#2a2a2a guifg=#d0d0d0 ctermbg=235 ctermfg=252

" 2. 当前选中的那一项：暗蓝色背景（#3a5a7a），白色文字（#ffffff）
highlight CocPumSel       guibg=#3a5a7a guifg=#ffffff ctermbg=24  ctermfg=15
highlight PmenuSel        guibg=#3a5a7a guifg=#ffffff ctermbg=24  ctermfg=15

" 3. 补全菜单的滚动条（防止滚动条也刺眼）
highlight PmenuSbar       guibg=#1a1a1a ctermbg=233
highlight PmenuThumb      guibg=#4a4a4a ctermbg=239


let mapleader = " "

" ============================================
" NERDTree 真正正确的配置
" ============================================

" 空格+e 打开/关闭文件树 (这里彻底去掉了多余的 <)
nnoremap <Leader>e :NERDTreeToggle<CR>

" 空格+E 在文件树中定位当前文件
nnoremap <Leader>E :NERDTreeFind<CR>

" 当 NERDTree 是唯一窗口时自动关闭 Vim
autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif

let loaded_matchparen = 1

" 实用小设置
let NERDTreeShowHidden=1        " 显示隐藏文件
let NERDTreeMinimalUI=1         " 干净的UI界面
let NERDTreeDirArrows=1         " 用箭头代替旧版的 + 
" 启用 powerline 符号支持
let g:airline_powerline_fonts = 1

" 智能回车终极版：如果是文件夹则展开/折叠，如果是文件则用新标签页打开
function! NERDTreeSmartEnter()
    " 获取当前选中的节点
    let l:node = g:NERDTreeFileNode.GetSelected()
    if !empty(l:node)
        if l:node.path.isDirectory
            " 解决方案：直接调用 NERDTree 的核心 API 来切换目录展开状态
            " 这样既不依赖容易变动的 ActivateNode，也不会误触右侧窗口的 modifiable 限制
            call l:node.activate({'reuse': 1, 'where': 'p'})
        else
            " 如果是文件，依然调用 API 在新 Tab 中打开
            call l:node.open({'where': 't'})
        endif
    endif
endfunction

" 重新将 NERDTree 的回车键绑定到这个终极函数上
autocmd FileType nerdtree nnoremap <buffer> <CR> :call NERDTreeSmartEnter()<CR>

" 重新将 NERDTree 的回车键绑定到修复后的函数上
autocmd FileType nerdtree nnoremap <buffer> <CR> :call NERDTreeSmartEnter()<CR>

" 将 NERDTree 的回车键绑定到这个智能函数上
autocmd FileType nerdtree nnoremap <buffer> <CR> :call NERDTreeSmartEnter()<CR>








" ============================================
" CoC 智能补全快捷键配置
" ============================================

" 1. 按 Tab 键：如果菜单出来了就向下选，否则就打出正常的 Tab
inoremap <silent><expr> <TAB>
      \ coc#pum#visible() ? coc#pum#next(1) :
      \ CheckBackspace() ? "\<Tab>" :
      \ coc#refresh()

" 2. 按 Shift + Tab 键：在菜单里向上选择
inoremap <expr><S-TAB> coc#pum#visible() ? coc#pum#prev(1) : "\<C-h>"

" 3. 按 回车键(Enter)：确认补全（把 ran 变成 range 并关掉菜单）
inoremap <silent><expr> <CR> coc#pum#visible() ? coc#pum#confirm()
                              \: "\<C-g>u\<CR>\<c-r>=coc#on_enter()\<CR>"

" 4. 辅助函数：判断光标前是不是空格
function! CheckBackspace() abort
  let col = col('.') - 1
  return !col || getline('.')[col - 1]  =~# '\s'
endfunction
