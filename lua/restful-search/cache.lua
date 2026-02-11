-- restful-search/cache.lua
-- 缓存扫描结果，避免重复扫描

local M = {}

local _cache = {
	endpoints = nil, -- 缓存的端点列表
	root_dir = nil, -- 缓存对应的项目根目录
	timestamp = 0, -- 缓存时间戳
}

--- 获取缓存的端点列表
---@return table[]|nil
function M.get()
	return _cache.endpoints
end

--- 获取缓存对应的根目录
---@return string|nil
function M.get_root_dir()
	return _cache.root_dir
end

--- 设置缓存
---@param endpoints table[]
---@param root_dir string
function M.set(endpoints, root_dir)
	_cache.endpoints = endpoints
	_cache.root_dir = root_dir
	_cache.timestamp = os.time()
end

--- 清除缓存
function M.clear()
	_cache.endpoints = nil
	_cache.root_dir = nil
	_cache.timestamp = 0
end

--- 检查缓存是否有效
---@param root_dir string
---@return boolean
function M.is_valid(root_dir)
	return _cache.endpoints ~= nil and _cache.root_dir == root_dir
end

--- 获取缓存信息（用于调试）
---@return table
function M.info()
	return {
		has_cache = _cache.endpoints ~= nil,
		root_dir = _cache.root_dir,
		endpoint_count = _cache.endpoints and #_cache.endpoints or 0,
		timestamp = _cache.timestamp,
		age_seconds = _cache.timestamp > 0 and (os.time() - _cache.timestamp) or 0,
	}
end

return M
