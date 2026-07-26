# Finder Terminal Agent 规范

## 开发规范

1. 使用中文回答。
2. 方法必须添加中文注释。
3. 日志必须使用中文。
4. 禁止使用强解包。
5. 最终回复必须说明使用过的插件、技能和工具。

## 交付规范

1. 功能修改完成并验证通过后，代码直接提交并推送到 `main`；除非用户明确要求，否则不创建 PR。
2. 每次发布都必须更新版本号，构建并验证 Universal Release 产物，然后创建正式 GitHub Release。
3. GitHub Release 必须上传 `Finder.Terminal.zip`、`Finder.Terminal.Source.zip` 和 `Finder.Terminal.Icon.png`。
4. Release 发布完成后，将 `Finder Terminal.app` 迁移到 `/Applications`，替换前先确认目标并退出旧版本。
5. 最终回复必须报告测试结果、提交、标签、Release 地址、本地安装路径和产物校验值。
