-- restful-search/init.lua
-- 插件入口：setup、search、refresh 等

local scanner = require("restful-search.scanner")
local cache = require("restful-search.cache")

local M = {}

local _config = {
	-- 项目根目录检测标记文件
	root_markers = { "pom.xml", "build.gradle", ".git" },
}

--- 检测项目根目录（优先 .git，避免被子模块 pom.xml 截断）
---@return string
local function detect_root_dir()
	-- 优先用 .git 找到真正的项目根
	local git_root = vim.fs.root(0, { ".git" })
	if git_root then
		return git_root
	end
	-- 回退到其他标记
	local root = vim.fs.root(0, _config.root_markers)
	if root then
		return root
	end
	-- 最终回退到 cwd
	return vim.fn.getcwd()
end

--- 格式化端点为显示字符串
---@param endpoint table
---@return string
local function format_endpoint(endpoint)
	local method = string.format("%-7s", endpoint.http_method)
	local filename = vim.fn.fnamemodify(endpoint.file, ":t")
	return string.format("%s %s  →  %s:%d", method, endpoint.path, filename, endpoint.line)
end

--- 获取端点列表（带缓存）
---@param force_refresh boolean|nil
---@return table[]
local function get_endpoints(force_refresh)
	local root_dir = detect_root_dir()

	if not force_refresh and cache.is_valid(root_dir) then
		return cache.get()
	end

	vim.notify("[RestfulSearch] 扫描中...", vim.log.levels.INFO)
	local endpoints = scanner.scan(root_dir)
	cache.set(endpoints, root_dir)
	vim.notify(string.format("[RestfulSearch] 扫描完成，共 %d 个端点", #endpoints), vim.log.levels.INFO)

	return endpoints
end

--- 跳转到端点
---@param endpoint table
local function goto_endpoint(endpoint)
	if vim.g.vscode then
		local vscode = require("vscode")
		-- 使用 vscode.eval 直接调用 VSCode API 打开文件并跳转
		vscode.eval_async(
			[[
			const uri = vscode.Uri.file(args[0]);
			const line = args[1] - 1;
			const doc = await vscode.workspace.openTextDocument(uri);
			const editor = await vscode.window.showTextDocument(doc, { preview: false });
			const pos = new vscode.Position(line, 0);
			editor.selection = new vscode.Selection(pos, pos);
			editor.revealRange(new vscode.Range(pos, pos), vscode.TextEditorRevealType.InCenter);
		]],
			{ args = { endpoint.file, endpoint.line } }
		)
	else
		vim.cmd("edit " .. vim.fn.fnameescape(endpoint.file))
		vim.api.nvim_win_set_cursor(0, { endpoint.line, 0 })
		vim.cmd("normal! zz")
	end
end

--- 使用 Snacks picker 搜索（带高亮，与 <leader>sg 风格一致）
---@param endpoints table[]
local function search_with_snacks(endpoints)
	local items = {}
	for _, ep in ipairs(endpoints) do
		table.insert(items, {
			text = format_endpoint(ep),
			file = ep.file,
			pos = { ep.line, 0 },
			endpoint = ep,
		})
	end

	require("snacks").picker({
		title = "RestfulSearch - API Endpoints",
		items = items,
		format = function(item, picker)
			local ep = item.endpoint
			local method = string.format("%-7s", ep.http_method or "GET")
			local filename = vim.fn.fnamemodify(ep.file, ":t")
			-- 分段高亮：METHOD | PATH | → | file:line（与 Snacks grep/file 一致，便于模糊匹配高亮）
			return {
				{ method, "SnacksPickerGitType" },
				{ ep.path, "SnacksPickerFile" },
				{ "  →  ", "SnacksPickerDelim" },
				{ filename .. ":" .. ep.line, "SnacksPickerRow" },
			}
		end,
		confirm = function(picker, item)
			picker:close()
			if item then
				goto_endpoint(item.endpoint)
			end
		end,
		preview = "file",
	})
end

--- 使用 Telescope 搜索
---@param endpoints table[]
local function search_with_telescope(endpoints)
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	pickers
		.new({}, {
			prompt_title = "RestfulSearch - API Endpoints",
			finder = finders.new_table({
				results = endpoints,
				entry_maker = function(entry)
					local display = format_endpoint(entry)
					return {
						value = entry,
						display = display,
						ordinal = entry.http_method .. " " .. entry.path .. " " .. entry.class_name,
						filename = entry.file,
						lnum = entry.line,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = conf.grep_previewer({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						goto_endpoint(selection.value)
					end
				end)
				return true
			end,
		})
		:find()
end

--- 使用 vim.ui.select 搜索（Cursor 环境）
---@param endpoints table[]
local function search_with_ui_select(endpoints)
	local items = {}
	for _, ep in ipairs(endpoints) do
		table.insert(items, format_endpoint(ep))
	end

	vim.ui.select(items, {
		prompt = "RestfulSearch - API Endpoints:",
	}, function(choice, idx)
		if idx then
			goto_endpoint(endpoints[idx])
		end
	end)
end

--- 搜索 API 端点（主入口）
---@param opts table|nil { force_refresh = false }
function M.search(opts)
	opts = opts or {}
	local endpoints = get_endpoints(opts.force_refresh)

	if #endpoints == 0 then
		vim.notify("[RestfulSearch] 未找到任何 API 端点", vim.log.levels.WARN)
		return
	end

	-- 根据环境选择 UI：Cursor → vim.ui.select，终端 → Snacks > Telescope > vim.ui.select
	if vim.g.vscode then
		search_with_ui_select(endpoints)
	else
		local has_snacks, _ = pcall(require, "snacks")
		local has_telescope, _ = pcall(require, "telescope")
		if has_snacks then
			search_with_snacks(endpoints)
		elseif has_telescope then
			search_with_telescope(endpoints)
		else
			search_with_ui_select(endpoints)
		end
	end
end

--- 刷新缓存
function M.refresh()
	cache.clear()
	M.search({ force_refresh = true })
end

--- 显示缓存信息
function M.info()
	local info = cache.info()
	vim.notify(
		string.format(
			"[RestfulSearch] 缓存: %s, 端点: %d, 根目录: %s, 缓存时长: %ds",
			info.has_cache and "有" or "无",
			info.endpoint_count,
			info.root_dir or "无",
			info.age_seconds
		),
		vim.log.levels.INFO
	)
end

--- 插件初始化
---@param opts table|nil
function M.setup(opts)
	opts = opts or {}
	_config = vim.tbl_deep_extend("force", _config, opts)

	-- 注册用户命令
	vim.api.nvim_create_user_command("RestfulSearch", function()
		M.search()
	end, { desc = "Search API endpoints" })

	vim.api.nvim_create_user_command("RestfulSearchRefresh", function()
		M.refresh()
	end, { desc = "Refresh and search API endpoints" })

	vim.api.nvim_create_user_command("RestfulSearchInfo", function()
		M.info()
	end, { desc = "Show RestfulSearch cache info" })
end

return M
