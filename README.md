# EnglishCoach (macOS)

本地英语学习应用 MVP，已实现：

- 默认触发方式：连续复制两次 `⌘C, ⌘C`
- 跨应用读取选中文本（授权辅助功能后）/ 无权限时自动回退剪贴板
- 翻译结果展示（本地词典 + 在线回退）
- 查词历史本地持久化（SQLite）
- 手动输入支持回车直接翻译
- 历史记录支持删除（右键或鼠标悬停显示删除图标）
- 兴趣内容学习流：按主题（电影/科技/旅行/游戏/音乐）生成短篇阅读与选择题，显示今日完成数 / 连胜天数
- 软件内单词学习功能：每天 20 个单词（词义/例句），翻译可反复显示/再次隐藏，支持 ← → Space ⌘D 键盘操作；“标记熟悉”后从后续学习中剔除
- 统计总览增强：新增今日单词数、今日熟悉数、累计熟悉数
- 划词翻译可一键「加入生词本」：单个英文单词点按钮即进入每日学习与 SRS 复习队列（已缓存释义，单词卡即时显示，无需再次联网）
- 划词时自动记录原句上下文：授权辅助功能后，翻译会读取所选单词所在的句子，展示在翻译结果卡与查词历史中，复习时能结合真实语境

## 运行

### 方式 A：生成可双击启动的独立 App（推荐）

```bash
./scripts/build_app.sh
open ./dist/EnglishCoach.app
```

说明：

- 首次构建会自动生成三套图标：
  `Resources/AppIcon-pending-1024.png`
  `Resources/AppIcon-completed-1024.png`
  `Resources/AppIcon-completed-glow-1024.png`
- 会自动打包 `AppIconPending.icns` / `AppIconCompleted.icns` / `AppIconCompletedGlow.icns`
- App 运行时会根据“今天兴趣学习是否完成”自动切换 Dock 图标，并在完成时播放一次短脉冲动画
- 构建后可直接双击启动：`dist/EnglishCoach.app`
- 如果希望放到应用程序目录：

```bash
cp -R ./dist/EnglishCoach.app /Applications/
open /Applications/EnglishCoach.app
```

### 自定义 App 图标

1. 准备三张 1024x1024 PNG（未完成/已完成/完成发光帧）  
2. 分别覆盖：
   `Resources/AppIcon-pending-1024.png`
   `Resources/AppIcon-completed-1024.png`
   `Resources/AppIcon-completed-glow-1024.png`
3. 重新执行：

```bash
./scripts/build_app.sh
```

### 方式 B：终端直接运行

1. 构建（当前环境需显式指定 SDK）：

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
SWIFT_MODULE_CACHE_PATH=/tmp/swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
swift build --disable-sandbox
```

2. 启动：

```bash
./.build/arm64-apple-macosx/debug/EnglishCoach
```

## 软件内单词学习使用

- 在主窗口中使用 `每日单词学习` 卡片
- 单词按顺序展示，可手动切换上一个/下一个
- 点击 `标记熟悉` 后会自动切换到下一个单词，并把该词从后续学习中移除
- 主界面统计中的 `累计熟悉` 可点击查看全部熟悉单词，并支持取消熟悉

## 首次权限

- 打开系统设置 -> 隐私与安全性 -> 辅助功能
- 允许应用访问辅助功能后，可直接读取当前选中文本
- 不授权也能用：通过连续复制两次 `⌘C, ⌘C` 走剪贴板翻译

## 数据位置

SQLite 文件：

```text
~/Library/Application Support/EnglishCoach/english_coach.sqlite3
```
