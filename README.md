# Finder Terminal

Finder Terminal 是一个原生 macOS 菜单栏工具。Finder 位于前台时按 `⌃⌥T`，它会根据当前选择解析目录并打开终端新窗口。

> 从 v1.0.1 起，默认快捷键由 `⌘⇧T` 调整为 `⌃⌥T`，避免与 Finder 自带的“显示/隐藏标签页栏”冲突。升级后会自动迁移旧版默认配置，用户自定义快捷键不会被覆盖。

## 路径规则

- 选中文件夹：打开该文件夹。
- 选中文件或 App 文件包：打开其父目录。
- 没有选择项目：打开当前 Finder 窗口目录。
- 没有 Finder 窗口：打开桌面目录。
- 同时选择多个项目：使用 Finder 返回的第一个项目。

## 支持的终端

- Apple Terminal
- iTerm2
- Warp
- Ghostty

设置中只展示当前已安装的终端。已选择的第三方终端被卸载后，会自动回退系统“终端”。

## 开发与构建

环境要求：

- macOS 13 或更高版本
- Xcode 26
- XcodeGen

执行：

```bash
chmod +x scripts/build.sh
./scripts/build.sh
```

生成的应用位于：

```text
DerivedData/Build/Products/Release/FinderTerminal.app
```

## 首次使用

1. 启动 `FinderTerminal.app`（系统界面显示名称为“Finder Terminal”）。
2. 在欢迎页选择是否登录时启动。
3. 点击“授权并测试”。
4. macOS 弹出自动化权限请求时，允许 Finder Terminal 控制 Finder。
5. 如需修改权限，前往“系统设置 → 隐私与安全性 → 自动化”。

如果菜单栏或设置页提示快捷键未生效，说明该组合可能已被其他应用占用，请在设置页重新录入一个快捷键。

## 隐私

应用只在本机读取 Finder 当前选中项目或窗口目录，不上传文件名、路径或任何文件内容。
