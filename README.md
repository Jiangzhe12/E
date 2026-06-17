# EnglishCoach (macOS)

本地英语学习应用 MVP，已实现：

- 默认触发方式：连续复制两次 `⌘C, ⌘C`
- 跨应用读取选中文本（授权辅助功能后）/ 无权限时自动回退剪贴板
- 翻译结果展示：ECDICT 本地词典优先，句子/词典未命中内容可走 Claude CLI（安全隔离）、Claude API 或 MyMemory 回退
- 单次翻译输入上限：2000 字符
- 查词历史本地持久化（SQLite）
- 手动输入支持回车直接翻译
- 历史记录支持删除（右键或鼠标悬停显示删除图标）
- 兴趣内容学习流：按主题（电影/科技/旅行/游戏/音乐）生成短篇阅读与选择题，显示今日完成数 / 连胜天数
- 软件内单词学习功能：默认每天 20 个单词（词义/例句），完成后显示“今日已完成”；可点“学习下一组”继续扩展到 40/60/...，进度同步显示在主窗口和桌宠气泡
- 统计总览增强：新增今日单词数、今日熟悉数、累计熟悉数
- 熟悉单词列表增强：支持“今日/全部”筛选，按日期分组，展示音标、翻译、英文释义、熟悉时间和下次复习状态
- 划词翻译可一键「加入生词本」：单个英文单词点按钮即进入每日学习与 SRS 复习队列（已缓存释义，单词卡即时显示，无需再次联网）
- 划词时自动记录原句上下文：授权辅助功能后，翻译会读取所选单词所在的句子，展示在翻译结果卡与查词历史中，复习时能结合真实语境
- 学习路线板块（面向「开会能跟上、能开口」）：以能力进阶分关卡（句块速记 → 跟读 → 中译英产出 → 角色扮演）。
  - 「关卡1 · 会议口语句块」——内置高频会议/通话句块库（没听清、争取时间、表态异议、收尾、寒暄五类），复用单词的 SRS 复习引擎；卡片采用「产出优先」设计：正面只给中文场景，先在脑中说出英文再揭晓对照，可朗读、标记掌握并进入间隔复习
  - 「关卡3 · 中译英产出 + AI 批改」——内置工作/会议语境的中译英题，用户写出英文后由 Claude（本地 CLI 或 API）批改，返回评级（很地道/基本可用/可以更好）、更地道的改写版本（可朗读）、1-3 条中文反馈与参考答案；批改次数计入活跃度与连胜。`freeOnly` 引擎下提示需切换到 AI 引擎
- 待办清单（从独立 TodoList app 原生并入）：主窗口「待办」分页支持快速添加、详细新建（分类 功能/Bug/优化、优先级、截止日期、备注、Bug 详情）、状态切换（待办→进行中→已完成）、按日期分组、搜索/分类/状态筛选、删除并 4 秒内撤销；跨天自动顺延（未完成顺延到今天、过期已完成自动归档）；首次启动一次性导入旧 app 的历史待办；桌宠菜单可「快速记待办」（读剪贴板）、「今日待办」（气泡内直接标记完成 / 打开列表）

## 运行

### 方式 A：生成可双击启动的独立 App（推荐）

```bash
./scripts/build_app.sh
open /Applications/EnglishCoach.app
```

说明：

- 首次构建会自动生成三套图标：
  `Resources/AppIcon-pending-1024.png`
  `Resources/AppIcon-completed-1024.png`
  `Resources/AppIcon-completed-glow-1024.png`
- 会自动打包 `AppIconPending.icns` / `AppIconCompleted.icns` / `AppIconCompletedGlow.icns`
- App 运行时会根据“今天兴趣学习是否完成”自动切换 Dock 图标，并在完成时播放一次短脉冲动画
- 构建产物会生成到 `dist/EnglishCoach.app`
- 脚本会自动替换 `/Applications/EnglishCoach.app`，推荐直接从 `/Applications` 启动最新版

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

## 翻译引擎与隐私

翻译链路按优先级执行：

1. 英文单词/短语优先查本地 `ECDICT`，不联网，速度最快。
2. 句子或本地词典未命中内容根据设置选择：
   - `本地 Claude CLI（安全隔离）`：使用本机已登录的 Claude Code，无需 API Key；调用时禁用 Claude Code 工具、禁用会话持久化、忽略 MCP 配置，并在 `/tmp/EnglishCoachClaudeCLI` 临时空目录运行，避免访问项目文件。
   - `Claude API Key`：使用 Anthropic API，速度和稳定性通常优于 CLI，但需要配置 API Key。
   - `仅免费（MyMemory）`：不调用 Claude，质量一般，作为免费兜底。
3. Claude 调用失败时会回退到 MyMemory，并在结果里提示来源。

本地 Claude CLI 仍会比普通 HTTP API 慢，因为每次翻译都要启动一次 CLI 进程。

## 软件内单词学习使用

- 在主窗口中使用 `每日单词学习` 卡片
- 默认每日目标为 20 个新词，进度显示为 `1/20`、`2/20` ...
- 达到目标后显示 `今日已完成`，不再继续展示新词卡
- 点击 `学习下一组` 后，当天目标扩展到 `40`，进度从 `21/40` 继续；之后可继续扩展到 `60`、`80` ...
- 单词按顺序展示，可手动切换上一个/下一个；翻译可显示/再次隐藏
- 点击 `标记熟悉` 后会自动切换到下一个单词，并把该词加入间隔复习
- 主界面统计中的 `今日熟悉` / `累计熟悉` 可点击查看熟悉单词；列表支持今日/全部、日期分组、释义展示和取消熟悉

## 首次权限

- 打开系统设置 -> 隐私与安全性 -> 辅助功能
- 允许应用访问辅助功能后，可直接读取当前选中文本
- 不授权也能用：通过连续复制两次 `⌘C, ⌘C` 走剪贴板翻译

## 数据位置

SQLite 文件：

```text
~/Library/Application Support/EnglishCoach/english_coach.sqlite3
```

## 开发验证

常用验证命令：

```bash
swift build --disable-sandbox
swiftc Sources/EnglishCoach/Models.swift Sources/EnglishCoach/MeetingPhraseBank.swift Sources/EnglishCoach/ProductionDrill.swift Sources/EnglishCoach/ClaudeTranslationProvider.swift Sources/EnglishCoach/ClaudeCLITranslationProvider.swift Tests/ClaudeCLISafetyTests/main.swift -o /tmp/ClaudeCLISafetyTests && /tmp/ClaudeCLISafetyTests
swiftc Sources/EnglishCoach/WordCarouselStore.swift Tests/WordCarouselStoreTests/main.swift -o /tmp/WordCarouselStoreTests && /tmp/WordCarouselStoreTests
swiftc Sources/EnglishCoach/DailyWordProgress.swift Tests/DailyWordProgressTests/main.swift -o /tmp/DailyWordProgressTests && /tmp/DailyWordProgressTests
swiftc Sources/EnglishCoach/TodoModels.swift Sources/EnglishCoach/TodoCarryOver.swift Tests/TodoCarryOverTests/main.swift -o /tmp/TodoCarryOverTests && /tmp/TodoCarryOverTests
swiftc Sources/EnglishCoach/TodoModels.swift Sources/EnglishCoach/LegacyTodoDecoder.swift Tests/TodoMigrationMappingTests/main.swift -o /tmp/TodoMigrationMappingTests && /tmp/TodoMigrationMappingTests
swiftc Sources/EnglishCoach/TodoModels.swift Sources/EnglishCoach/TodoCarryOver.swift Sources/EnglishCoach/LegacyTodoDecoder.swift Sources/EnglishCoach/TodoStore.swift Tests/TodoStoreCRUDTests/main.swift -lsqlite3 -o /tmp/TodoStoreCRUDTests && /tmp/TodoStoreCRUDTests
```
