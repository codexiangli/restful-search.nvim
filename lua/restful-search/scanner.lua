-- restful-search/scanner.lua
-- 两遍扫描：先扫 Controller 找 implements 关系，再扫接口提取路径

local parser = require("restful-search.parser")

local M = {}

--- 递归查找所有 Java 文件
---@param dir string
---@return string[]
local function find_java_files(dir)
	local cmd = string.format("find %s -name '*.java' -type f 2>/dev/null", vim.fn.shellescape(dir))
	local output = vim.fn.systemlist(cmd)
	if vim.v.shell_error ~= 0 then
		return {}
	end
	return output
end

--- 根据接口名查找接口文件
---@param all_files string[]
---@param interface_name string
---@return string|nil filepath
local function find_interface_file(all_files, interface_name)
	local target = interface_name .. ".java"
	for _, f in ipairs(all_files) do
		if f:match(target .. "$") then
			return f
		end
	end
	return nil
end

--- 确保路径以 / 开头
---@param path string
---@return string
local function normalize_path(path)
	if not path or path == "" then
		return ""
	end
	if path:sub(1, 1) ~= "/" then
		path = "/" .. path
	end
	-- 去掉尾部 /
	if #path > 1 and path:sub(-1) == "/" then
		path = path:sub(1, -2)
	end
	return path
end

--- 扫描项目，返回所有 API 端点列表
---@param root_dir string 项目根目录
---@return table[] endpoints { http_method, path, file, line, method_name, class_name }
function M.scan(root_dir)
	local endpoints = {}
	local all_files = find_java_files(root_dir)

	if #all_files == 0 then
		vim.notify("[RestfulSearch] 未找到 Java 文件", vim.log.levels.WARN)
		return endpoints
	end

	-- ============ 第一遍：解析所有文件 ============
	local parsed_files = {} -- filepath -> parse_result
	local controllers = {} -- 只有 @RestController 的文件
	local feign_clients = {} -- @FeignClient 的文件
	local interfaces = {} -- class_name -> parse_result

	for _, filepath in ipairs(all_files) do
		local info = parser.parse_file(filepath)
		if info.class_name then
			parsed_files[filepath] = info
			if info.is_controller then
				table.insert(controllers, info)
			end
			if info.is_feign_client then
				table.insert(feign_clients, info)
			end
			if info.is_interface and info.class_path then
				interfaces[info.class_name] = info
			end
		end
	end

	-- ============ 第二遍：构建端点列表 ============
	for _, ctrl in ipairs(controllers) do
		local class_path = ""
		local iface_info = nil

		-- 情况1：Controller 通过 implements 接口，注解在接口上
		if ctrl.interface_name and interfaces[ctrl.interface_name] then
			iface_info = interfaces[ctrl.interface_name]
			class_path = normalize_path(iface_info.class_path or "")

			-- 遍历接口方法，匹配到 Controller 的实现行号
			for _, iface_method in ipairs(iface_info.methods) do
				if iface_method.path then
					local method_path = normalize_path(iface_method.path)
					local full_path = class_path .. method_path

					-- 查找 Controller 中对应的实现方法行号
					local target_line = nil
					for _, ctrl_method in ipairs(ctrl.methods) do
						if ctrl_method.name == iface_method.name then
							target_line = ctrl_method.line
							break
						end
					end

					table.insert(endpoints, {
						http_method = iface_method.http_method or "REQUEST",
						path = full_path,
						-- 跳转到接口声明
						file = iface_info.filepath,
						line = iface_method.line,
						method_name = iface_method.name,
						class_name = iface_info.class_name,
						-- 保留 Controller 实现信息
						impl_file = ctrl.filepath,
						impl_line = target_line or 1,
						impl_class_name = ctrl.class_name,
					})
				end
			end
		end

		-- 情况2：注解直接写在 Controller 上
		if ctrl.class_path then
			class_path = normalize_path(ctrl.class_path)
		end

		for _, method in ipairs(ctrl.methods) do
			if method.path and not method.has_override then
				-- 非 @Override 方法，注解在 Controller 上
				local method_path = normalize_path(method.path)
				local full_path
				if ctrl.class_path then
					full_path = normalize_path(ctrl.class_path) .. method_path
				else
					full_path = class_path .. method_path
				end

				table.insert(endpoints, {
					http_method = method.http_method or "REQUEST",
					path = full_path,
					file = ctrl.filepath,
					line = method.line,
					method_name = method.name,
					class_name = ctrl.class_name,
				})
			end
		end
	end

	-- ============ 第三遍：处理 FeignClient ============
	-- 已有端点路径集合（避免重复）
	local existing_paths = {}
	for _, ep in ipairs(endpoints) do
		existing_paths[ep.path] = true
	end

	for _, feign in ipairs(feign_clients) do
		-- FeignClient extends 的接口
		local iface_name = feign.extends_name
		if iface_name and interfaces[iface_name] then
			local iface_info = interfaces[iface_name]
			local feign_base = normalize_path(feign.feign_path or "")
			local class_path = feign_base ~= "" and feign_base or normalize_path(iface_info.class_path or "")

			for _, iface_method in ipairs(iface_info.methods) do
				if iface_method.path then
					local method_path = normalize_path(iface_method.path)
					local full_path = class_path .. method_path

					-- 只添加还没被 Controller 覆盖的端点
					if not existing_paths[full_path] then
						table.insert(endpoints, {
							http_method = iface_method.http_method or "REQUEST",
							path = full_path,
							file = iface_info.filepath,
							line = iface_method.line,
							method_name = iface_method.name,
							class_name = feign.class_name .. " [Feign]",
							feign_name = feign.feign_name,
						})
						existing_paths[full_path] = true
					end
				end
			end
		end

		-- FeignClient 自己也有 @RequestMapping（不通过 extends）
		if feign.class_path then
			local class_path = normalize_path(feign.feign_path or feign.class_path or "")
			for _, method in ipairs(feign.methods) do
				if method.path then
					local method_path = normalize_path(method.path)
					local full_path = class_path .. method_path

					if not existing_paths[full_path] then
						table.insert(endpoints, {
							http_method = method.http_method or "REQUEST",
							path = full_path,
							file = feign.filepath,
							line = method.line,
							method_name = method.name,
							class_name = feign.class_name .. " [Feign]",
							feign_name = feign.feign_name,
						})
						existing_paths[full_path] = true
					end
				end
			end
		end
	end

	-- 按路径排序
	table.sort(endpoints, function(a, b)
		return a.path < b.path
	end)

	return endpoints
end

return M
