// MARK: - SettingsView.swift
// お掃除ロボット顔アプリ - 設定画面
// iOS 18+ / Swift 6 / SwiftUI
//
// ユーザーがアプリの動作をカスタマイズするための設定画面。
// 映像設定、ネットワーク情報、デバッグ機能を提供する。
// 運用時はアクセスガイドにより通常アクセスできない前提だが、
// デバッグ・初期セットアップ時に使用する。
//
// preview.html の Settings Screen Tab を忠実に再現:
//   - .settings-content: 背景 #1c1c1e
//   - .settings-header: "Settings" + "Done" ボタン
//   - セクション: Video Settings / Network / RTSP Streaming / System / Display / Debug
//   - .settings-row: iOS標準の grouped list 行スタイル
//   - .icon-*: 各セクションのアイコン背景色

import SwiftUI

// MARK: - 設定画面メインビュー

struct SettingsView: View {
    @Bindable var appState: RobotAppState
    @Environment(\.dismiss) private var dismiss

    @State private var showResetConfirmation: Bool = false
    @State private var showEmotionPicker: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                // ── 映像設定セクション ──
                videoSettingsSection

                // ── ネットワーク情報セクション ──
                networkInfoSection

                // ── RTSP配信ステータスセクション ──
                streamingStatusSection

                // ── システム情報セクション ──
                systemInfoSection

                // ── 表示設定セクション ──
                displaySettingsSection

                // ── デバッグセクション ──
                debugSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("アプリをリセットしますか？", isPresented: $showResetConfirmation) {
                Button("リセット", role: .destructive) {
                    resetApp()
                }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("すべての設定が初期値に戻り、RTSP配信が再起動されます。")
            }
        }
    }

    // MARK: - 映像設定セクション
    // preview.html: Video Settings / icon-video (#5856d6 purple)

    private var videoSettingsSection: some View {
        Section {
            // 解像度選択
            // preview.html: 📹 Resolution → "720p (1280x720) ▾"
            Picker(selection: $appState.resolution) {
                ForEach(VideoResolution.allCases) { resolution in
                    Text(resolution.rawValue).tag(resolution)
                }
            } label: {
                Label {
                    Text("映像解像度")
                } icon: {
                    SettingsIcon(systemName: "video.fill", background: .purple)
                }
            }
            .pickerStyle(.menu)

            // フレームレート選択
            // preview.html: ⏱ Frame Rate → "15 fps ▾"
            Picker(selection: $appState.frameRate) {
                ForEach(VideoFrameRate.allCases) { fps in
                    Text(fps.displayName).tag(fps)
                }
            } label: {
                Label {
                    Text("フレームレート")
                } icon: {
                    SettingsIcon(systemName: "clock.fill", background: .purple)
                }
            }
            .pickerStyle(.menu)

            // エンコード情報（読み取り専用）
            // preview.html: ⚙ Encoder → "H.264 (HW)"
            HStack {
                Label {
                    Text("エンコーダー")
                } icon: {
                    SettingsIcon(systemName: "cpu", background: .purple)
                }
                Spacer()
                Text("H.264 (Hardware)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("映像設定", systemImage: "video")
        } footer: {
            Text("解像度を下げると消費電力と発熱を抑えられます。720pで十分な監視品質を確保できます。")
        }
    }

    // MARK: - ネットワーク情報セクション
    // preview.html: Network / icon-network (#34c759 green)

    private var networkInfoSection: some View {
        Section {
            // Wi-Fi接続状態
            HStack {
                Label {
                    Text("Wi-Fi")
                } icon: {
                    SettingsIcon(systemName: "wifi", background: .green)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.networkStatus.indicatorColor)
                        .frame(width: 8, height: 8)
                    Text(appState.networkStatus.displayName)
                        .foregroundStyle(.secondary)
                }
            }

            // SSID
            HStack {
                Label {
                    Text("SSID")
                } icon: {
                    SettingsIcon(systemName: "antenna.radiowaves.left.and.right", background: .green)
                }
                Spacer()
                Text(appState.ssid)
                    .foregroundStyle(.secondary)
            }

            // IPアドレス
            HStack {
                Label {
                    Text("IPアドレス")
                } icon: {
                    SettingsIcon(systemName: "number", background: .green)
                }
                Spacer()
                Text(appState.ipAddress)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            // RTSPポート
            HStack {
                Label {
                    Text("RTSPポート")
                } icon: {
                    SettingsIcon(
                        systemName: "antenna.radiowaves.left.and.right",
                        background: .green
                    )
                }
                Spacer()
                Text("\(appState.rtspPort)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // RTSP URL（コピー可能）
            // preview.html: .url-box { background: #1c1c1e; color: #0a84ff; }
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("配信URL")
                } icon: {
                    SettingsIcon(systemName: "link", background: .green)
                }
                Text(appState.rtspURL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.blue)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        } header: {
            Label("ネットワーク", systemImage: "network")
        }
    }

    // MARK: - RTSP配信ステータスセクション
    // preview.html: RTSP Streaming / icon-stream (#ff9500 orange)

    private var streamingStatusSection: some View {
        Section {
            // 配信状態
            HStack {
                Label {
                    Text("配信状態")
                } icon: {
                    SettingsIcon(
                        systemName: "dot.radiowaves.left.and.right",
                        background: .orange
                    )
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.streamingStatus.indicatorColor)
                        .frame(width: 8, height: 8)
                    Text(appState.streamingStatus.displayName)
                        .foregroundStyle(.secondary)
                }
            }

            // 接続クライアント数
            HStack {
                Label {
                    Text("接続クライアント数")
                } icon: {
                    SettingsIcon(systemName: "person.fill", background: .orange)
                }
                Spacer()
                Text("\(appState.connectedClientCount)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("RTSP配信", systemImage: "play.circle")
        }
    }

    // MARK: - システム情報セクション
    // preview.html: System / icon-system (#007aff blue)

    private var systemInfoSection: some View {
        Section {
            // バッテリー
            HStack {
                Label {
                    Text("バッテリー")
                } icon: {
                    SettingsIcon(systemName: batteryIcon, background: .blue)
                }
                Spacer()
                HStack(spacing: 4) {
                    if appState.isCharging {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.green)
                            .font(.caption2)
                    }
                    Text("\(Int(appState.batteryLevel * 100))%")
                        .foregroundStyle(batteryColor)
                }
            }

            // CPU温度
            HStack {
                Label {
                    Text("CPU温度")
                } icon: {
                    SettingsIcon(systemName: "thermometer.medium", background: .blue)
                }
                Spacer()
                Text(String(format: "%.1f℃", appState.cpuTemperature))
                    .foregroundStyle(temperatureColor)
            }

            // 稼働時間
            HStack {
                Label {
                    Text("稼働時間")
                } icon: {
                    SettingsIcon(systemName: "clock", background: .blue)
                }
                Spacer()
                Text(appState.uptimeDisplay)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("システム状態", systemImage: "gearshape.2")
        }
    }

    // MARK: - 表示設定セクション
    // preview.html: Display / icon-display (#af52de purple)

    private var displaySettingsSection: some View {
        Section {
            // 表情プレビュー＆手動選択
            // preview.html: 😎 Expression Preview → "Normal >"
            NavigationLink {
                EmotionPickerView(appState: appState)
            } label: {
                HStack {
                    Label {
                        Text("表情プレビュー")
                    } icon: {
                        SettingsIcon(
                            systemName: "face.smiling",
                            background: Color(red: 0.686, green: 0.322, blue: 0.871) // #af52de
                        )
                    }
                    Spacer()
                    Text(appState.autoEmotion.displayName)
                        .foregroundStyle(.secondary)
                }
            }

            // デバッグオーバーレイ
            // preview.html: 🐛 Debug Info → toggle (off by default)
            Toggle(isOn: $appState.isDebugMode) {
                Label {
                    Text("デバッグ情報表示")
                } icon: {
                    SettingsIcon(
                        systemName: "ladybug.fill",
                        background: Color(red: 0.686, green: 0.322, blue: 0.871) // #af52de
                    )
                }
            }
        } header: {
            Label("表示設定", systemImage: "eye")
        } footer: {
            Text("デバッグ情報を有効にすると、顔表示画面にIPアドレスや配信状態などのシステム情報が表示されます。運用時はオフにしてください。")
        }
    }

    // MARK: - デバッグセクション
    // preview.html: Debug / icon-debug (#ff3b30 red)

    private var debugSection: some View {
        Section {
            // RTSP配信の再起動
            // preview.html: 🔄 Restart RTSP (blue text)
            Button {
                // TODO: RTSP配信の再起動処理
            } label: {
                Label {
                    Text("RTSP配信を再起動")
                } icon: {
                    SettingsIcon(systemName: "arrow.clockwise", background: .red)
                }
            }

            // カメラセッションの再起動
            // preview.html: 📷 Restart Camera (blue text)
            Button {
                // TODO: カメラセッションの再起動処理
            } label: {
                Label {
                    Text("カメラセッションを再起動")
                } icon: {
                    SettingsIcon(systemName: "camera.fill", background: .red)
                }
            }

            // アプリ全体のリセット
            // preview.html: 🔄 Reset App (red text)
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label {
                    Text("アプリをリセット")
                } icon: {
                    SettingsIcon(
                        systemName: "arrow.counterclockwise",
                        background: .red
                    )
                }
            }
        } header: {
            Label("デバッグ", systemImage: "wrench.and.screwdriver")
        } footer: {
            Text("これらの操作はデバッグ・トラブルシューティング用です。通常の運用では使用しないでください。")
        }
    }

    // MARK: - Helper Properties

    private var batteryIcon: String {
        switch appState.batteryLevel {
        case 0..<0.1:  return "battery.0percent"
        case 0.1..<0.3: return "battery.25percent"
        case 0.3..<0.6: return "battery.50percent"
        case 0.6..<0.8: return "battery.75percent"
        default:        return "battery.100percent"
        }
    }

    private var batteryColor: Color {
        if appState.batteryLevel < 0.1 { return .red }
        if appState.batteryLevel < 0.2 { return .orange }
        return .secondary
    }

    private var temperatureColor: Color {
        if appState.cpuTemperature > 50 { return .red }
        if appState.cpuTemperature > 42 { return .orange }
        return .secondary
    }

    // MARK: - Actions

    private func resetApp() {
        appState.resolution = .hd720
        appState.frameRate = .fps15
        appState.isDebugMode = false
        appState.isCleaningMode = false
        appState.currentEmotion = .normal
        appState.isShowingMomentaryEmotion = false
    }
}

// MARK: - 設定行用アイコン

/// preview.html の .settings-row .icon に対応する色付きアイコン
/// 各セクションのアイコン背景色:
///   - icon-video:   #5856d6 (purple)
///   - icon-network: #34c759 (green)
///   - icon-stream:  #ff9500 (orange)
///   - icon-system:  #007aff (blue)
///   - icon-display: #af52de (purple)
///   - icon-debug:   #ff3b30 (red)
struct SettingsIcon: View {
    let systemName: String
    let background: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - 表情選択画面

struct EmotionPickerView: View {
    @Bindable var appState: RobotAppState

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(RobotEmotion.allCases) { emotion in
                    Button {
                        appState.currentEmotion = emotion
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.black)
                                    .frame(height: 100)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(
                                                appState.currentEmotion == emotion
                                                    ? Color.blue : Color.clear,
                                                lineWidth: 3
                                            )
                                    )

                                HStack(spacing: 16) {
                                    SingleEyeView(
                                        emotion: emotion,
                                        isBlinking: false,
                                        isLeftEye: true,
                                        size: 50
                                    )
                                    SingleEyeView(
                                        emotion: emotion,
                                        isBlinking: false,
                                        isLeftEye: false,
                                        size: 50
                                    )
                                }
                            }

                            Text(emotion.displayName)
                                .font(.caption)
                                .foregroundStyle(
                                    appState.currentEmotion == emotion
                                        ? .primary : .secondary
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("表情プレビュー")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview("設定画面") {
    let state = RobotAppState()
    state.streamingStatus = .streaming
    state.connectedClientCount = 2
    return SettingsView(appState: state)
}

#Preview("表情選択画面") {
    NavigationStack {
        let state = RobotAppState()
        EmotionPickerView(appState: state)
    }
}
