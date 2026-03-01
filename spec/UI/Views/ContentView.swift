// MARK: - ContentView.swift
// お掃除ロボット顔アプリ - メインナビゲーション
// iOS 18+ / Swift 6 / SwiftUI
//
// アプリのルートビュー。通常時は顔表示画面をフルスクリーンで表示し、
// 隠しジェスチャー（トリプルタップ）で設定画面を呼び出す。
// キオスクモード（アクセスガイド）ではジェスチャーが無効化されるため、
// 設定画面へのアクセスは運用開始前のセットアップ時に限られる。

import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    @State private var appState = RobotAppState()
    @State private var showSettings: Bool = false
    @State private var tapCount: Int = 0
    @State private var lastTapTime: Date = .distantPast

    /// 設定画面を開くために必要なトリプルタップの領域（画面右上隅）
    private let settingsTapAreaSize: CGFloat = 80

    var body: some View {
        ZStack {
            // ── メイン顔表示画面（常に表示） ──
            RobotFaceView(appState: appState)
                .ignoresSafeArea()

            // ── 設定画面アクセス用の隠しタップエリア ──
            VStack {
                HStack {
                    Spacer()
                    // 画面右上の透明タップエリア
                    Color.clear
                        .frame(
                            width: settingsTapAreaSize,
                            height: settingsTapAreaSize
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleSettingsTap()
                        }
                }
                Spacer()
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(appState: appState)
                .presentationDetents([.large])
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            disableIdleTimer()
        }
    }

    // MARK: - Private Methods

    /// トリプルタップの検出処理
    private func handleSettingsTap() {
        let now = Date()
        let timeSinceLastTap = now.timeIntervalSince(lastTapTime)

        if timeSinceLastTap < 0.5 {
            tapCount += 1
        } else {
            tapCount = 1
        }

        lastTapTime = now

        if tapCount >= 3 {
            tapCount = 0
            showSettings = true
        }
    }

    /// 自動スリープを無効化
    /// UIApplication.shared.isIdleTimerDisabled = true に相当
    private func disableIdleTimer() {
        // 実際の実装では以下のコードを使用:
        // UIApplication.shared.isIdleTimerDisabled = true
        //
        // 注: この設定はアプリが前面にある間のみ有効。
        // アクセスガイドと併用することで完全な常時点灯を実現する。
    }
}

// MARK: - Preview

#Preview("ContentView - 通常") {
    ContentView()
}
