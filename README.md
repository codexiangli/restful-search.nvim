# restful-search.nvim

在 Neovim 中搜索 Spring Boot 项目的 API 端点，支持自动拼接 Controller 类级别和方法级别的 `@RequestMapping` 路径。类似 IntelliJ IDEA 的 RestfulToolKit 插件。

## 功能特性

- 扫描项目中所有 `@RestController` / `@Controller` 的 API 端点
- 自动拼接类级别 `@RequestMapping` + 方法级别 `@GetMapping` 等注解的路径
- 支持 Controller `implements` 接口的模式（注解在接口上，实现在 Controller 中）
- 支持 `@FeignClient` 端点扫描
- 支持多种注解格式：`@GetMapping("/path")`、`@RequestMapping(value = "/path", method = RequestMethod.POST)` 等
- 终端 Neovim 使用 Telescope 搜索，Cursor/VSCode 使用 Quick Pick
- 内置缓存，首次扫描后即时搜索

## 效果预览

```
<leader>se  →  弹出搜索框
输入: /page/search
结果:
  POST    /operational-task/page/search  →  IOperationalTaskController.java:32
  GET     /receipt/page/search           →  IProductReceiptController.java:45
选中 → 跳转到对应接口声明
```

## 安装

### 方式一：本地目录（推荐开发阶段）

将插件目录放在 Neovim 配置中：

```
~/.config/nvim/lua/plugins/restful-search-nvim/
├── lua/
│   └── restful-search/
│       ├── init.lua
│       ├── parser.lua
│       ├── scanner.lua
│       └── cache.lua
└── plugin/
    └── restful-search.lua
```

lazy.nvim 配置：

```lua
-- ~/.config/nvim/lua/plugins/restful-search.lua
return {
    {
        dir = vim.fn.stdpath("config") .. "/lua/plugins/restful-search-nvim",
        name = "restful-search.nvim",
        config = function()
            require("restful-search").setup()
        end,
        keys = {
            { "<leader>se", function() require("restful-search").search() end,  desc = "Search API endpoints" },
            { "<leader>sE", function() require("restful-search").refresh() end, desc = "Refresh & search" },
        },
    },
}
```

### 方式二：从 GitHub 安装

```lua
-- lazy.nvim
return {
    {
        "codexiangli/restful-search.nvim",
        config = function()
            require("restful-search").setup()
        end,
        keys = {
            { "<leader>se", function() require("restful-search").search() end,  desc = "Search API endpoints" },
            { "<leader>sE", function() require("restful-search").refresh() end, desc = "Refresh & search" },
        },
    },
}
```

## 配置

```lua
require("restful-search").setup({
    -- 项目根目录检测标记文件
    root_markers = { "pom.xml", "build.gradle", ".git" },
})
```

## 命令

| 命令 | 功能 |
|------|------|
| `:RestfulSearch` | 搜索 API 端点 |
| `:RestfulSearchRefresh` | 清除缓存，重新扫描并搜索 |
| `:RestfulSearchInfo` | 显示缓存信息（端点数量、缓存时长等） |

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| `<leader>se` | 搜索 API 端点（首次自动扫描，之后使用缓存） |
| `<leader>sE` | 强制刷新缓存并搜索 |

## 支持的注解格式

```java
// 类级别
@RequestMapping("/api/user")
@RequestMapping(value = "/api/user")
@RequestMapping(value = "/api/user", produces = "application/json")

// 方法级别
@GetMapping("/info")
@PostMapping("/create")
@PutMapping(value = "/update")
@DeleteMapping("/delete")
@PatchMapping("/patch")
@RequestMapping(value = "/search", method = RequestMethod.POST)
```

## 支持的项目结构

### 结构一：注解在接口上，Controller 实现接口

```java
// 接口（注解在这里）
@RequestMapping("/api/user")
public interface IUserController {
    @GetMapping("/info")
    DataResponse<User> getUserInfo(@RequestParam Long id);
}

// Controller（实现在这里）
@RestController
public class UserController implements IUserController {
    @Override
    public DataResponse<User> getUserInfo(Long id) { ... }
}
```

搜索结果跳转到**接口声明**处。

### 结构二：注解直接在 Controller 上

```java
@RestController
@RequestMapping("/api/product")
public class ProductController {
    @GetMapping("/list")
    public DataResponse<List<Product>> list() { ... }
}
```

搜索结果跳转到 Controller 方法处。

### 结构三：FeignClient

```java
@FeignClient(name = "userClient", url = "${service.user}")
public interface UserClient extends IUserController {
}
```

如果 FeignClient extends 的接口在项目内且有对应 Controller，则不会重复显示。
如果没有对应 Controller（纯 FeignClient），会标注 `[Feign]` 并显示。

## Cursor/VSCode 兼容

插件自动检测 `vim.g.vscode` 环境：

- **终端 Neovim**：使用 Telescope picker（模糊搜索 + 文件预览）
- **Cursor/VSCode**：使用 `vim.ui.select`（VSCode Quick Pick 渲染）

在 Cursor 的 keymaps.lua 中需要额外添加映射：

```lua
if vim.g.vscode then
    vim.keymap.set("n", "<leader>se", function()
        require("restful-search").search()
    end, { desc = "Search API endpoints" })
    vim.keymap.set("n", "<leader>sE", function()
        require("restful-search").refresh()
    end, { desc = "Refresh & search API endpoints" })
end
```

## 插件架构

```
lua/restful-search/
├── init.lua      入口：setup()、search()、refresh()、info()
│                 - 检测项目根目录（优先 .git）
│                 - 管理缓存读写
│                 - 根据环境选择 Telescope 或 vim.ui.select
│
├── parser.lua    解析引擎
│                 - 解析 @RequestMapping/@GetMapping 等注解
│                 - 提取 implements/extends 关系
│                 - 提取 @FeignClient 注解
│                 - 解析方法签名和行号
│
├── scanner.lua   扫描器（三遍扫描）
│                 - 第一遍：解析所有 Java 文件，分类 Controller/Interface/FeignClient
│                 - 第二遍：构建 Controller 端点（拼接接口路径 + 匹配实现行号）
│                 - 第三遍：处理 FeignClient 端点（去重）
│
└── cache.lua     缓存
                  - 按项目根目录缓存
                  - 支持手动刷新
```

## 将插件上传到 GitHub

### 步骤一：创建独立项目目录

```bash
mkdir ~/projects/restful-search.nvim
cd ~/projects/restful-search.nvim
```

### 步骤二：复制插件文件

```bash
# 复制插件源码
mkdir -p lua/restful-search plugin
cp ~/.config/nvim/lua/plugins/restful-search-nvim/lua/restful-search/*.lua lua/restful-search/
cp ~/.config/nvim/lua/plugins/restful-search-nvim/plugin/*.lua plugin/

# 复制 README
cp ~/.config/nvim/lua/plugins/restful-search-nvim/README.md .
```

### 步骤三：最终目录结构

```
restful-search.nvim/
├── README.md
├── lua/
│   └── restful-search/
│       ├── init.lua
│       ├── parser.lua
│       ├── scanner.lua
│       └── cache.lua
└── plugin/
    └── restful-search.lua
```

### 步骤四：初始化 Git 并上传

```bash
cd ~/projects/restful-search.nvim
git init
git add .
git commit -m "feat: 初始版本 - Spring Boot API 端点搜索插件"

# 在 GitHub 上创建仓库后
git remote add origin git@github.com:你的用户名/restful-search.nvim.git
git branch -M main
git push -u origin main
```

### 步骤五：其他人如何使用

安装后在 lazy.nvim 中配置：

```lua
return {
    {
        "codexiangli/restful-search.nvim",
        dependencies = {
            "nvim-telescope/telescope.nvim", -- 可选，终端 Neovim 用
        },
        config = function()
            require("restful-search").setup()
        end,
        keys = {
            { "<leader>se", function() require("restful-search").search() end,  desc = "Search API endpoints" },
            { "<leader>sE", function() require("restful-search").refresh() end, desc = "Refresh & search" },
        },
    },
}
```

## 已知限制

1. **外部 jar 包中的 FeignClient 接口**无法扫描（源码在编译后的 .class 中）
2. 注解必须在**单行内完成**，不支持跨行注解
3. 首次扫描大型项目（3000+ Java 文件）可能需要几秒
4. 仅支持 Spring MVC 注解，不支持 JAX-RS（`@Path`、`@GET` 等）

## License

MIT
