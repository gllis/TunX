//
//  SettingsView.swift
//  TunX
//
//  Created by glli on 2026/8/18.
//

import SwiftUI

/// 应用设置：日志、开机自启与 SSH 保活参数。
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    private static let intervalPresets = [30, 60, 120, 300]
    private static let countPresets = [2, 3, 5, 10]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("设置")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(SettingsTheme.title)

            SettingsOptionRow(
                title: "显示日志",
                selection: $settings.showLogs,
                options: [
                    .init(value: false, title: "关闭", systemImage: "eye.slash"),
                    .init(value: true, title: "开启", systemImage: "eye")
                ]
            )

            VStack(alignment: .leading, spacing: 8) {
                SettingsOptionRow(
                    title: "开机自启",
                    selection: launchAtLoginBinding,
                    options: [
                        .init(value: false, title: "关闭", systemImage: "minus"),
                        .init(value: true, title: "开启", systemImage: "checkmark")
                    ]
                )
                if let message = settings.launchAtLoginMessage {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsIntRow(
                title: "ServerAliveInterval",
                value: $settings.serverAliveInterval,
                presets: Self.intervalPresets,
                unit: "秒",
                range: AppSettings.serverAliveIntervalRange
            )

            SettingsIntRow(
                title: "ServerAliveCountMax",
                value: $settings.serverAliveCountMax,
                presets: Self.countPresets,
                unit: nil,
                range: AppSettings.serverAliveCountMaxRange
            )

            Text("SSH 保活参数在下次连接时生效，间隔为 0 时关闭心跳。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(minWidth: 520, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(SettingsTheme.pageBackground(for: colorScheme))
        .onAppear {
            settings.refreshLaunchAtLogin()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { settings.setLaunchAtLogin($0) }
        )
    }
}

private struct SettingsChoice<Value: Hashable>: Identifiable {
    var id: Value { value }
    let value: Value
    let title: String
    let systemImage: String?
}

private struct SettingsOptionRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [SettingsChoice<Value>]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SettingsTheme.sectionTitle)

            HStack(spacing: 8) {
                ForEach(options) { option in
                    SettingsPill(
                        title: option.title,
                        systemImage: option.systemImage,
                        selected: selection == option.value
                    ) {
                        selection = option.value
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct SettingsIntRow: View {
    let title: String
    @Binding var value: Int
    let presets: [Int]
    let unit: String?
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SettingsTheme.sectionTitle)

            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { preset in
                    SettingsPill(
                        title: presetTitle(preset),
                        systemImage: nil,
                        selected: value == preset
                    ) {
                        value = preset
                    }
                }

                SettingsIntField(value: $value, unit: unit, selected: !presets.contains(value), range: range)
                Spacer(minLength: 0)
            }
        }
    }

    private func presetTitle(_ preset: Int) -> String {
        if let unit, !unit.isEmpty {
            return "\(preset) \(unit)"
        }
        return "\(preset)"
    }
}

private struct SettingsIntField: View {
    @Binding var value: Int
    let unit: String?
    let selected: Bool
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 4) {
            TextField(
                "",
                value: $value,
                format: IntegerFormatStyle<Int>().grouping(.never)
            )
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .frame(width: 40)
            .onSubmit {
                value = min(max(value, range.lowerBound), range.upperBound)
            }

            if let unit, !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? SettingsTheme.selectedFill : SettingsTheme.unselectedFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? SettingsTheme.selectedStroke : SettingsTheme.unselectedStroke, lineWidth: 1)
        )
    }
}

private struct SettingsPill: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let systemImage: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 13))
                    .fixedSize()
            }
            .foregroundStyle(SettingsTheme.controlForeground(for: colorScheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? SettingsTheme.selectedFill : SettingsTheme.unselectedFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? SettingsTheme.selectedStroke : SettingsTheme.unselectedStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private enum SettingsTheme {
    static let title = Color.primary
    static let sectionTitle = Color(nsColor: .secondaryLabelColor)

    static let selectedFill = Color(light: (0.90, 0.84, 0.84), dark: (0.36, 0.28, 0.29))
    static let selectedStroke = Color(light: (0.24, 0.24, 0.24), dark: (0.82, 0.78, 0.78))
    static let unselectedFill = Color(light: (0.95, 0.94, 0.93), dark: (0.22, 0.22, 0.23))
    static let unselectedStroke = Color(light: (0.90, 0.89, 0.87), dark: (0.32, 0.32, 0.33))

    static func pageBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(nsColor: .windowBackgroundColor)
            : Color(light: (0.976, 0.969, 0.961), dark: (0.11, 0.11, 0.12))
    }

    static func controlForeground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color(white: 0.18)
    }
}

private extension Color {
    init(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

#Preview {
    SettingsView()
}
