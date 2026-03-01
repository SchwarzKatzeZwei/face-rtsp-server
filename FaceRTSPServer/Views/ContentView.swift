// MARK: - ContentView.swift
// お掃除ロボット顔アプリ - メインナビゲーション
// iOS 18+ / Swift 6 / SwiftUI
//
// アプリのルートビュー。通常時は顔表示画面をフルスクリーンで表示し、
// 隠しジェスチャー（トリプルタップ）で設定画面を呼び出す。
// キオスクモード（アクセスガイド）ではジェスチャーが無効化されるため、
// 設定画面へのアクセスは運用開始前のセットアップ時に限られる。
//
// preview.html Screen Flow:
//   RobotFaceView (Always visible) → Triple-tap top-right corner → SettingsView (Modal .sheet)

import SwiftUI
import UIKit

// MARK: - ContentView

struct ContentView: View {
    @State private var appState = RobotAppState()
    @State private var showSettings: Bool = false
    @State private var tapCount: Int = 0
    @State private var lastTapTime: Date = .distantPast

    /// 設定画面を開くために必要なトリプルタップの領域（画面右上隅）
    /// preview.html Screen Flow: "Triple-tap top-right corner"
    private let settingsTapAreaSize: CGFloat = 80

    var body: some View {
        ZStack {
            // ── メイン顔表示画面（常に表示） ──
            RobotFaceView(appState: appState)
                .ignoresSafeArea()

            // ── 設定画面アクセス用の隠しタップエリア ──
            // preview.html: "☞ x3 Triple-tap top-right corner"
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
            appState.startUptimeTracking()
        }
        .onDisappear {
            appState.stopUptimeTracking()
        }
    }

    // MARK: - Private Methods

    /// トリプルタップの検出処理
    /// 0.5秒以内に3回タップで設定画面を表示
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
    /// plan.md: "UIApplication.shared.isIdleTimerDisabled プロパティを有効化し、
    ///          システムによる自動スリープをプログラムレベルでブロックする"
    private func disableIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = true
    }
}

// MARK: - Preview

#Preview("ContentView - 通常") {
    ContentView()
}
