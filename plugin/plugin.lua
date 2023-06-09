local m = require('moonwalk')

vim.keymap.set('n', '<C-s>', m.walk_to_top, { noremap = true, silent = true })
