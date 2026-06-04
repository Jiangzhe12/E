import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("翻译设置") {
                Toggle(
                    "桌宠翻译气泡",
                    isOn: Binding(
                        get: { model.translationPresentationMode == .floating },
                        set: { model.translationPresentationMode = $0 ? .floating : .mainWindow }
                    )
                )
                .toggleStyle(.switch)
                Text("开启后桌面会常驻一个翻译桌宠，⌘C⌘C 的译文会显示在它头上的气泡里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI 翻译（Claude）") {
                SecureField("API Key（sk-ant-...）", text: $model.claudeAPIKey)
                    .textFieldStyle(.roundedBorder)

                Picker("模型", selection: $model.claudeModel) {
                    ForEach(ClaudeTranslationProvider.availableModels, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                if model.claudeAPIKey.trimmed.isEmpty {
                    Label("未配置 API Key，句子翻译将使用免费的 MyMemory（质量一般）。", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("已启用 Claude 翻译：句子和词典未收录的内容都会由 Claude 翻译并附讲解。", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.22, green: 0.58, blue: 0.32))
                }
                Text("单词和短语优先查内置 ECDICT 离线词典（秒查、免费）；结果卡片会标注每次翻译的来源。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("辅助功能") {
                HStack {
                    if model.hasAccessibilityPermission {
                        Label("辅助功能权限已就绪", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(Color(red: 0.22, green: 0.58, blue: 0.32))
                    } else {
                        Label("未授权辅助功能", systemImage: "lock.shield")
                            .foregroundStyle(Color(red: 0.78, green: 0.44, blue: 0.12))
                        Spacer()
                        Button("授予辅助功能权限") {
                            model.requestAccessibilityPermission()
                        }
                    }
                }
                Text("授权后 ⌘C⌘C 识别更准确，并可读取其他 App 的选中文本。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("每日提醒") {
                Toggle(
                    "开启每日学习提醒",
                    isOn: Binding(
                        get: { model.reminderEnabled },
                        set: { newValue in
                            Task {
                                await model.updateReminderSettings(enabled: newValue, time: model.reminderTime)
                            }
                        }
                    )
                )
                .toggleStyle(.switch)

                if model.reminderEnabled {
                    DatePicker(
                        "提醒时间",
                        selection: Binding(
                            get: { model.reminderTime },
                            set: { newTime in
                                Task {
                                    await model.updateReminderSettings(enabled: true, time: newTime)
                                }
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }

                Text("每天到点若还没完成学习就提醒；当天完成后不会再弹出。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 450, minHeight: 300)
    }
}
