return {
	{
		"echasnovski/mini.nvim",
		branch = "stable",
		config = function()
			require("mini.pairs").setup({})
			require("mini.trailspace").setup({})
			require("mini.surround").setup({})
			require("mini.bufremove").setup({})
			require("mini.bracketed").setup({})

			local statusline = require("mini.statusline")
			statusline.setup({ use_icons = true })
			---@diagnostic disable-next-line: duplicate-set-field
			statusline.section_location = function()
				return "%2l:%-2v"
			end

			require("mini.tabline").setup({
				tabpage_section = "none",
			})
			vim.cmd([[ au FileType * if index(['gitcommit','fugitive'], &ft) >= 0 | let b:minitabline_disable=v:true | endif ]])
		end,
	},
}
