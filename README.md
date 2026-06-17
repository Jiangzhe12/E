# Nova（macOS）

> 你的桌面学习与待办伙伴 —— 一只住在屏幕角落、随进度发光的小星云。

**Nova** 是一个本地优先的 macOS 桌面伙伴，把三件事揉进一只可爱的桌宠里：

- 🗣️ **学英语**（划词翻译 · 每日单词 · SRS 复习 · 兴趣阅读 · 面向「开会能开口」的学习路线 + AI 批改）
- ✅ **管待办**（快速记 · 详细新建 · 状态流转 · 跨天顺延 · 周报）
- 🐾 **桌宠陪伴**（随「今日是否完成」切换 Dock 图标并发光，气泡提醒、右键速记）

---

## 功能特性

### 划词翻译
- 默认触发：连续复制两次 `⌘C, ⌘C`
- 跨应用读取选中文本（授权辅助功能后）；无权限时自动回退剪贴板
- 翻译链路：ECDICT 本地词典优先 → 句子/未命中走 Claude CLI（安全隔离）/ Claude API / MyMemory 兜底
- 单次翻译上限 2000 字符；手动输入支持回车直接翻译
- 自动记录原句上下文：复习时能结合真实语境
- 单个英文单词可一键「加入生词本」，直接进入每日学习与 SRS 复习队列（已缓存释义，单词卡即时显示）
- 查词历史本地持久化（SQLite），支持右键/悬停删除

### 每日单词学习（SRS）
- 默认每天 20 个新词（词义 / 例句），完成后显示「今日已完成」
- 可点「学习下一组」扩展到 40 / 60 / …，进度同步显示在主窗口与桌宠气泡
- 「标记熟悉」后自动切到下一词并进入间隔复习
- 熟悉单词列表支持「今日 / 全部」筛选、按日期分组，展示音标、翻译、英文释义、熟悉时间与下次复习状态

### 兴趣内容学习流
- 按主题（电影 / 科技 / 旅行 / 游戏 / 音乐）生成短篇阅读 + 选择题
- 显示今日完成数 / 连胜天数

### 学习路线（面向「开会能跟上、能开口」）
按能力进阶分关卡：句块速记 → 跟读 → 中译英产出 → 角色扮演。

- **关卡 1 · 会议口语句块**：内置高频会议 / 通话句块库（没听清、争取时间、表态异议、收尾、寒暄五类），复用单词的 SRS 复习引擎；卡片「产出优先」——正面只给中文场景，先在脑中说出英文再揭晓对照，可朗读、标记掌握并进入间隔复习。
- **关卡 3 · 中译英产出 + AI 批改**：内置工作 / 会议语境的中译英题，用户写出英文后由 Claude（本地 CLI 或 API）批改，返回评级（很地道 / 基本可用 / 可以更好）、更地道的改写版本（可朗读）、1–3 条中文反馈与参考答案；批改计入活跃度与连胜。`freeOnly` 引擎下会提示切换到 AI 引擎。

### 待办清单（原生并入，原 TodoList app）
- 主窗口「待办」分页：快速添加、详细新建（分类 功能 / Bug / 优化、优先级、截止日期、备注、Bug 详情）
- 状态切换（待办 → 进行中 → 已完成）、按日期分组、搜索 / 分类 / 状态筛选
- 删除后 4 秒内可撤销
- 跨天自动顺延：未完成顺延到今天、过期已完成自动归档
- 首次启动一次性导入旧 app 的历史待办

### 桌宠交互
- 随「今日兴趣学习是否完成」自动切换 Dock 图标，完成时播放一次短脉冲发光动画
- 右键菜单可「快速记待办」（读剪贴板）、「今日待办」（气泡内直接标记完成 / 打开列表）
- 进度气泡同步显示单词学习进度

### 统计总览
- 今日单词数、今日熟悉数、累计熟悉数；熟悉数可点击查看明细

---

## 运行

### 方式 A：生成可双击启动的独立 App（推荐）

```bash
./scripts/build_app.sh
open /Applications/Nova.app
```

说明：

- 首次构建会自动生成三套图标：
  - `Resources/AppIcon-pending-1024.png`
  - `Resources/AppIcon-completed-1024.png`
  - `Resources/AppIcon-completed-glow-1024.png`
- 会自动打包 `AppIconPending.icns` / `AppIconCompleted.icns` / `AppIconCompletedGlow.icns`
- App 运行时会根据「今天兴趣学习是否完成」自动切换 Dock 图标，完成时播放一次短脉冲动画
- 构建产物生成到 `dist/Nova.app`，脚本会自动替换 `/Applications/Nova.app`，推荐直接从 `/Applications` 启动最新版

#### 自定义 App 图标

1. 准备三张 1024×1024 PNG（未完成 / 已完成 / 完成发光帧）
2. 分别覆盖：
   - `Resources/AppIcon-pending-1024.png`
   - `Resources/AppIcon-completed-1024.png`
   - `Resources/AppIcon-completed-glow-1024.png`
3. 重新执行 `./scripts/build_app.sh`

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
./.build/arm64-apple-macosx/debug/Nova
```

---

## 翻译引擎与隐私

翻译链路按优先级执行：

1. 英文单词 / 短语优先查本地 `ECDICT`，不联网，速度最快。
2. 句子或本地词典未命中内容，根据设置选择：
   - **本地 Claude CLI（安全隔离）**：使用本机已登录的 Claude Code，无需 API Key；调用时禁用 Claude Code 工具、禁用会话持久化、忽略 MCP 配置，并在 `/tmp/NovaClaudeCLI` 临时空目录运行，避免访问项目文件。
   - **Claude API Key**：使用 Anthropic API，速度和稳定性通常优于 CLI，但需要配置 API Key。
   - **仅免费（MyMemory）**：不调用 Claude，质量一般，作为免费兜底。
3. Claude 调用失败时回退到 MyMemory，并在结果里提示来源。

> 本地 Claude CLI 仍会比普通 HTTP API 慢，因为每次翻译都要启动一次 CLI 进程。

---

## 首次权限

- 打开 系统设置 → 隐私与安全性 → 辅助功能
- 允许应用访问辅助功能后，可直接读取当前选中文本
- 不授权也能用：通过连续复制两次 `⌘C, ⌘C` 走剪贴板翻译

---

## 数据位置

SQLite 文件：

```text
~/Library/Application Support/Nova/english_coach.sqlite3
```

---

## 开发验证

常用验证命令：

```bash
swift build --disable-sandbox
swiftc Sources/Nova/Models.swift Sources/Nova/MeetingPhraseBank.swift Sources/Nova/ProductionDrill.swift Sources/Nova/ClaudeTranslationProvider.swift Sources/Nova/ClaudeCLITranslationProvider.swift Tests/ClaudeCLISafetyTests/main.swift -o /tmp/ClaudeCLISafetyTests && /tmp/ClaudeCLISafetyTests
swiftc Sources/Nova/WordCarouselStore.swift Tests/WordCarouselStoreTests/main.swift -o /tmp/WordCarouselStoreTests && /tmp/WordCarouselStoreTests
swiftc Sources/Nova/DailyWordProgress.swift Tests/DailyWordProgressTests/main.swift -o /tmp/DailyWordProgressTests && /tmp/DailyWordProgressTests
swiftc Sources/Nova/TodoModels.swift Sources/Nova/TodoCarryOver.swift Tests/TodoCarryOverTests/main.swift -o /tmp/TodoCarryOverTests && /tmp/TodoCarryOverTests
swiftc Sources/Nova/TodoModels.swift Sources/Nova/LegacyTodoDecoder.swift Tests/TodoMigrationMappingTests/main.swift -o /tmp/TodoMigrationMappingTests && /tmp/TodoMigrationMappingTests
swiftc Sources/Nova/TodoModels.swift Sources/Nova/TodoCarryOver.swift Sources/Nova/LegacyTodoDecoder.swift Sources/Nova/TodoStore.swift Tests/TodoStoreCRUDTests/main.swift -lsqlite3 -o /tmp/TodoStoreCRUDTests && /tmp/TodoStoreCRUDTests
swiftc Sources/Nova/TodoModels.swift Sources/Nova/TodoFilter.swift Tests/TodoFilterSortTests/main.swift -o /tmp/TodoFilterSortTests && /tmp/TodoFilterSortTests
swiftc Sources/Nova/TodoModels.swift Sources/Nova/TodoStats.swift Tests/TodoStatsTests/main.swift -o /tmp/TodoStatsTests && /tmp/TodoStatsTests
swiftc Sources/Nova/TodoModels.swift Sources/Nova/WeeklyReport.swift Tests/WeeklyReportTests/main.swift -o /tmp/WeeklyReportTests && /tmp/WeeklyReportTests
swiftc Sources/Nova/TodoModels.swift Tests/TodoTemplateTests/main.swift -o /tmp/TodoTemplateTests && /tmp/TodoTemplateTests
```

---

## 关于名字

应用原名 **EnglishCoach**。随着待办清单、桌宠交互等能力并入，「英语教练」已不足以概括它的定位，
因此更名为 **Nova** —— 取自桌宠那只随你进度逐渐变亮、会发光的小星云。新名字与具体功能解耦，
能同时覆盖「学英语」和「管待办」两条主线。
