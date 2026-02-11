-- restful-search/parser.lua
-- 解析 Java 文件中的 Spring 注解和 implements 关系

local M = {}

-- HTTP method 映射
local MAPPING_ANNOTATIONS = {
	["RequestMapping"] = false, -- method 由参数决定，false 表示需要从参数中提取
	["GetMapping"] = "GET",
	["PostMapping"] = "POST",
	["PutMapping"] = "PUT",
	["DeleteMapping"] = "DELETE",
	["PatchMapping"] = "PATCH",
}

--- 从注解字符串中提取路径
--- 处理格式：
---   @GetMapping("/path")
---   @RequestMapping(value = "/path")
---   @RequestMapping(value = "/path", method = RequestMethod.POST)
---   @PostMapping(value = "/path")
---@param annotation_str string 注解内容（括号内）
---@return string|nil path
local function extract_path(annotation_str)
	if not annotation_str or annotation_str == "" then
		return nil
	end

	-- 直接字符串: @GetMapping("/path") 或 @GetMapping("path")
	local path = annotation_str:match('^"([^"]*)"')
	if path then
		return path
	end

	-- value = "/path" 或 value = "path"
	path = annotation_str:match('value%s*=%s*"([^"]*)"')
	if path then
		return path
	end

	-- path = "/path"
	path = annotation_str:match('path%s*=%s*"([^"]*)"')
	if path then
		return path
	end

	return nil
end

--- 从 @RequestMapping 注解中提取 HTTP method
---@param annotation_str string
---@return string
local function extract_request_method(annotation_str)
	if not annotation_str then
		return "REQUEST"
	end

	local method = annotation_str:match("RequestMethod%.(%w+)")
	if method then
		return method
	end

	return "REQUEST"
end

--- 解析单行注解，返回 { path, http_method } 或 nil
---@param line string
---@return table|nil
function M.parse_mapping_annotation(line)
	for annotation, default_method in pairs(MAPPING_ANNOTATIONS) do
		-- 匹配 @Annotation("...") 或 @Annotation(...)
		local params = line:match("@" .. annotation .. "%s*%((.-)%)")
		if params then
			local path = extract_path(params)
			local http_method = default_method or extract_request_method(params)
			return {
				path = path or "",
				http_method = http_method,
			}
		end

		-- 匹配 @Annotation (无括号，无路径)
		if line:match("@" .. annotation .. "%s*$") then
			return {
				path = "",
				http_method = default_method or "REQUEST",
			}
		end
	end

	return nil
end

--- 从类声明行中提取 implements 的接口名
--- 处理: public class XxxController implements IXxxController {
---@param line string
---@return string|nil interface_name
function M.parse_implements(line)
	local iface = line:match("implements%s+([%w_]+)")
	return iface
end

--- 从方法签名中提取方法名
--- 处理: public DataResponse<...> getByTaskSerialNo(...) {
---       PageListResponse<List<...>> pageSearch(...)
---@param line string
---@return string|nil method_name
function M.parse_method_name(line)
	-- 匹配方法声明：返回类型 方法名(
	-- 需要处理泛型类型如 DataResponse<List<Xxx>>
	local name = line:match("%s+([%w_]+)%s*%(")
	if name then
		-- 排除关键字
		local keywords = { "if", "for", "while", "switch", "catch", "return", "new", "class", "interface", "enum" }
		for _, kw in ipairs(keywords) do
			if name == kw then
				return nil
			end
		end
		return name
	end
	return nil
end

--- 检查是否是 @RestController 或 @Controller 类
---@param line string
---@return boolean
function M.is_controller_annotation(line)
	return line:match("@RestController") ~= nil or line:match("@Controller") ~= nil
end

--- 检查是否有 @Override
---@param line string
---@return boolean
function M.is_override(line)
	return line:match("@Override") ~= nil
end

--- 解析一个 Java 文件，返回结构化信息
---@param filepath string
---@return table file_info
function M.parse_file(filepath)
	local lines = vim.fn.readfile(filepath)
	if not lines or #lines == 0 then
		return {}
	end

	local result = {
		filepath = filepath,
		class_path = nil, -- 类级别 @RequestMapping 路径
		class_http_method = nil,
		interface_name = nil, -- implements 的接口名
		extends_name = nil, -- extends 的接口名（FeignClient 用）
		is_controller = false, -- 是否是 @RestController
		is_interface = false, -- 是否是 interface
		is_feign_client = false, -- 是否是 @FeignClient
		feign_path = nil, -- @FeignClient 的 path 参数
		feign_name = nil, -- @FeignClient 的 name 参数
		class_name = nil,
		methods = {}, -- { name, line, path, http_method, has_override }
	}

	local pending_annotation = nil -- 暂存的注解信息（可能跨行）
	local pending_override = false
	local in_class_header = true -- 还没进入方法区域

	for i, line in ipairs(lines) do
		local trimmed = vim.trim(line)

		-- 检查 @RestController / @Controller
		if M.is_controller_annotation(trimmed) then
			result.is_controller = true
		end

		-- 检查 @FeignClient
		if trimmed:match("@FeignClient") then
			result.is_feign_client = true
			-- 提取 name 参数
			result.feign_name = trimmed:match('name%s*=%s*"([^"]*)"')
			-- 提取 path 参数（如果有）
			result.feign_path = trimmed:match('path%s*=%s*"([^"]*)"')
		end

		-- 检查 interface 声明
		if trimmed:match("^public%s+interface%s+") then
			result.is_interface = true
			local class_name = trimmed:match("interface%s+([%w_]+)")
			result.class_name = class_name
			-- 提取 extends
			result.extends_name = trimmed:match("extends%s+([%w_]+)")
			in_class_header = false
		end

		-- 检查 class 声明和 implements
		if trimmed:match("^public%s+class%s+") then
			local class_name = trimmed:match("class%s+([%w_]+)")
			result.class_name = class_name
			result.interface_name = M.parse_implements(trimmed)
			in_class_header = false
		end

		-- 解析 mapping 注解
		local mapping = M.parse_mapping_annotation(trimmed)
		if mapping then
			if in_class_header or (result.is_interface and not pending_annotation and not trimmed:match("%(")) then
				-- 类/接口级别注解（在 class/interface 声明之前）
				if not result.class_name then
					result.class_path = mapping.path
					result.class_http_method = mapping.http_method
				else
					-- 方法级别注解
					pending_annotation = mapping
				end
			else
				-- 方法级别注解
				pending_annotation = mapping
			end
		end

		-- 检查 @Override
		if M.is_override(trimmed) then
			pending_override = true
		end

		-- 如果有 pending_annotation，尝试匹配方法名
		if pending_annotation and result.class_name then
			local method_name = M.parse_method_name(trimmed)
			if method_name then
				table.insert(result.methods, {
					name = method_name,
					line = i,
					path = pending_annotation.path,
					http_method = pending_annotation.http_method,
					has_override = pending_override,
				})
				pending_annotation = nil
				pending_override = false
			end
		end

		-- 如果遇到方法签名但没有 pending_annotation（如 @Override 后的无注解方法）
		if not pending_annotation and pending_override then
			local method_name = M.parse_method_name(trimmed)
			if method_name then
				table.insert(result.methods, {
					name = method_name,
					line = i,
					path = nil,
					http_method = nil,
					has_override = true,
				})
				pending_override = false
			end
		end
	end

	return result
end

return M
