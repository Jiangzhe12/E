import SwiftUI

/// A sheet listing every keyboard shortcut the app exposes, so users don't have
/// to memorize them. Triggered from the main window via `Shift + /` (i.e. `?`).
struct ShortcutHelpView: View {
    var onClose: () -> Void

    private struct ShortcutItem: Identifiable {
        let id = UUID()
        let keys: [String]
        let description: String
    }

    private struct ShortcutGroup: Identifiable {
        let id = UUID()
        let title: String
        let items: [ShortcutItem]
    }

    private let groups: [ShortcutGroup] = [
        ShortcutGroup(
            title: "翻译",
            items: [
                ShortcutItem(keys: ["⌘", "E"], description: "打开快速翻译输入窗口"),
                ShortcutItem(keys: ["⌘", "C"], description: "连按两次：翻译当前选中的文本"),
                ShortcutItem(keys: ["⇧", "⌘", "T"], description: "翻译剪贴板里的内容"),
                ShortcutItem(keys: ["⌘", "⏎"], description: "在菜单栏浮窗里提交翻译"),
                ShortcutItem(keys: ["Esc"], description: "关闭翻译浮窗 / 弹出的 sheet")
            ]
        ),
        ShortcutGroup(
            title: "每日单词",
            items: [
                ShortcutItem(keys: ["空格"], description: "显示或隐藏当前单词的翻译"),
                ShortcutItem(keys: ["←"], description: "上一个单词"),
                ShortcutItem(keys: ["→"], description: "下一个单词"),
                ShortcutItem(keys: ["⌘", "D"], description: "新词：标记为熟悉"),
                ShortcutItem(keys: ["R"], description: "复习词:「还记得」,进入下一个间隔"),
                ShortcutItem(keys: ["F"], description: "复习词:「忘了」,明天再来一次"),
                ShortcutItem(keys: ["⌘", "P"], description: "朗读当前单词")
            ]
        ),
        ShortcutGroup(
            title: "导航",
            items: [
                ShortcutItem(keys: ["⌘", "F"], description: "聚焦历史搜索框"),
                ShortcutItem(keys: ["⇧", "?"], description: "显示本快捷键帮助")
            ]
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("快捷键速查", systemImage: "keyboard")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(red: 0.13, green: 0.30, blue: 0.50))
                Spacer()
                Button("关闭") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(red: 0.22, green: 0.44, blue: 0.64))
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(group.items) { item in
                                    shortcutRow(item)
                                }
                            }
                        }
                    }

                    Text("提示：⌘C⌘C 需要「辅助功能」权限才能读取其他 App 的选中文本。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 440, minHeight: 460)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 0.93, green: 0.96, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private func shortcutRow(_ item: ShortcutItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Array(item.keys.enumerated()), id: \.offset) { _, key in
                    keyCap(key)
                }
            }
            .frame(minWidth: 110, alignment: .leading)

            Text(item.description)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func keyCap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(red: 0.13, green: 0.30, blue: 0.50))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color(red: 0.78, green: 0.84, blue: 0.90), lineWidth: 1)
                    )
            )
    }
}
