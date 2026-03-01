// MARK: - RobotFaceApp.swift
// お掃除ロボット顔アプリ - アプリケーションエントリーポイント
// iOS 18+ / Swift 6 / SwiftUI
//
// @main で指定されるアプリケーションのルート。
// SceneDelegateの代わりにSwiftUIのAppプロトコルを使用し、
// WindowGroupで単一のメインシーンを定義する。

import SwiftUI

@main
struct RobotFaceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .persistentSystemOverlays(.hidden)
        }
    }
}
