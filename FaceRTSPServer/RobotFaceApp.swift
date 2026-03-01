// MARK: - RobotFaceApp.swift
// お掃除ロボット顔アプリ - アプリケーションエントリーポイント
// iOS 18+ / Swift 6 / SwiftUI
//
// @main で指定されるアプリケーションのルート。
// SwiftUIのAppプロトコルを使用し、WindowGroupで単一のメインシーンを定義する。
//
// plan.md の要件:
//   - 常時画面点灯（isIdleTimerDisabled は ContentView.onAppear で設定）
//   - システムオーバーレイ非表示（.persistentSystemOverlays(.hidden)）
//   - ScenePhase 監視によるバックグラウンド復帰時の適切なリカバリ

import SwiftUI

@main
struct RobotFaceApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .persistentSystemOverlays(.hidden)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // フォアグラウンド復帰時: 自動スリープ無効を再確認
                UIApplication.shared.isIdleTimerDisabled = true
            case .background:
                // バックグラウンド遷移時: カメラ・RTSP は別途 Actor で継続管理
                break
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
