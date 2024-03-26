return {
	{ "tpope/vim-fugitive", dependencies = { "tpope/vim-rhubarb", "shumphrey/fugitive-gitlab.vim" } },
	{ "nvim-tree/nvim-tree.lua", opts = {} },
	{
		"j-hui/fidget.nvim",
		opts = {
			integration = {
				["nvim-tree"] = { enable = true },
			},
		},
	},
	{
		"akinsho/toggleterm.nvim",
		tag = "v2.6.0",
		opts = {
			open_mapping = [[<c-\>]],
			direction = "float",
			shell = vim.o.shell,
			float_opts = {
				border = "rounded",
			},
		},
	},
	{
		"folke/trouble.nvim",
		dependencies = { "devicons" },
		config = function()
			require("trouble").setup({})

			vim.keymap.set("n", "<leader>xx", function()
				require("trouble").toggle()
			end)
			vim.keymap.set("n", "<leader>xw", function()
				require("trouble").toggle("workspace_diagnostics")
			end)
			vim.keymap.set("n", "<leader>xd", function()
				require("trouble").toggle("document_diagnostics")
			end)
			vim.keymap.set("n", "<leader>xq", function()
				require("trouble").toggle("quickfix")
			end)
			vim.keymap.set("n", "<leader>xl", function()
				require("trouble").toggle("loclist")
			end)
			vim.keymap.set("n", "gR", function()
				require("trouble").toggle("lsp_references")
			end)
		end,
	},
	{
		"vim-test/vim-test",
		config = function()
			vim.cmd([[ let test#strategy='toggleterm' ]])
		end,
	},
	{
		"nvim-neotest/neotest",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"antoinemadec/FixCursorHold.nvim",
			"nvim-neotest/neotest-python",
			"nvim-neotest/neotest-vim-test",
		},
	},
}
