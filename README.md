# restful-search.nvim

在 Neovim 中搜索 Spring Boot 项目的 API 端点，支持自动拼接 Controller 类级别和方法级别的 `@RequestMapping` 路径。类似 IntelliJ IDEA 的 RestfulToolKit 插件。

## 功能特性

- 扫描项目中所有 `@RestController` / `@Controller` 的 API 端点
- 自动拼接类级别 `@RequestMapping` + 方法级别 `@GetMapping` 等注解的路径
- 支持 Controller `implements` 接口的模式（注解在接口上，实现在 Controller 中）
- 支持 `@FeignClient` 端点扫描
- 支持多种注解格式：`@GetMapping("/path")`、`@RequestMapping(value = "/path", method = RequestMethod.POST)` 等
- 终端 Neovim 使用 Snacks/Telescope 搜索，Cursor/VSCode 使用 Quick Pick
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

```lua
-- lazy.nvim
return {
    {
        "codexiangli/restful-search.nvim",
        dependencies = {
            "folke/snacks.nvim", -- 可选，终端 Neovim 用
            "nvim-telescope/telescope.nvim", -- 可选，终端 Neovim 用
        },
        config = function()
            require("restful-search").setup({
                root_markers = { "pom.xml", "build.gradle", ".git" },
            })
        end,
        keys = {
            { "<leader>se", function() require("restful-search").search() end,  desc = "Search API endpoints" },
            { "<leader>sE", function() require("restful-search").refresh() end, desc = "Refresh & search" },
        },
    },
}
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

- **终端 Neovim**：使用 Snacks pickewr / Telescope picker（模糊搜索 + 文件预览）
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

## 已知限制

1. **外部 jar 包中的 FeignClient 接口**无法扫描（源码在编译后的 .class 中）
2. 注解必须在**单行内完成**，不支持跨行注解
3. 首次扫描大型项目（3000+ Java 文件）可能需要几秒
4. 仅支持 Spring MVC 注解，不支持 JAX-RS（`@Path`、`@GET` 等）

## License

MIT
