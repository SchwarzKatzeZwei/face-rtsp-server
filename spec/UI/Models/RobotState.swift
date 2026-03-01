// MARK: - RobotState.swift
// お掃除ロボット顔アプリ - 状態管理モデル
// iOS 18+ / Swift 6 / SwiftUI

import SwiftUI

// MARK: - ロボットの感情・表情状態

/// ロボットの表情を定義する列挙型
/// 各ケースが目の描画パラメータに直接マッピングされる
enum RobotEmotion: String, CaseIterable, Identifiable {
    case normal       // 通常状態 - 穏やかな丸い目
    case happy        // 嬉しい - 目が弧を描いて笑顔
    case sleepy       // 眠そう - 半分閉じた目
    case surprised    // 驚き - 大きく見開いた目
    case wink         // ウインク - 片目を閉じる（RTSP接続時）
    case error        // エラー - ×印の目
    case lowBattery   // バッテリー低下 - 眠そう＋下がった目
    case cleaning     // 掃除中 - キラキラした嬉しい目
    case charging     // 充電中 - 穏やかな半目（リラックス）

    var id: String { rawValue }

    /// 表情に対応する目の開き具合 (0.0: 完全に閉じた状態 ~ 1.0: 完全に開いた状態)
    var eyeOpenness: CGFloat {
        switch self {
        case .normal:     return 0.85
        case .happy:      return 0.6
        case .sleepy:     return 0.35
        case .surprised:  return 1.0
        case .wink:       return 0.85  // 開いている方の目
        case .error:      return 0.7
        case .lowBattery: return 0.25
        case .cleaning:   return 0.75
        case .charging:   return 0.4
        }
    }

    /// 目のサイズスケール (1.0 が基準)
    var eyeScale: CGFloat {
        switch self {
        case .normal:     return 1.0
        case .happy:      return 1.05
        case .sleepy:     return 0.9
        case .surprised:  return 1.2
        case .wink:       return 1.05
        case .error:      return 0.95
        case .lowBattery: return 0.85
        case .cleaning:   return 1.1
        case .charging:   return 0.95
        }
    }

    /// 目の色
    var eyeColor: Color {
        switch self {
        case .normal:     return .white
        case .happy:      return .cyan
        case .sleepy:     return Color(white: 0.7)
        case .surprised:  return .white
        case .wink:       return .cyan
        case .error:      return .red
        case .lowBattery: return .orange
        case .cleaning:   return .green
        case .charging:   return Color(red: 0.4, green: 0.8, blue: 1.0)
        }
    }

    /// 瞳孔（ハイライト）の色
    var pupilHighlightColor: Color {
        switch self {
        case .error:      return .clear
        case .lowBattery: return .yellow.opacity(0.3)
        default:          return .white.opacity(0.8)
        }
    }

    /// 目のカーブ方向 (正: 笑顔弧, 0: ニュートラル, 負: 悲しい弧)
    var eyeCurve: CGFloat {
        switch self {
        case .happy, .cleaning:  return 0.4
        case .charging:          return 0.2
        case .sleepy, .lowBattery: return -0.1
        default:                 return 0.0
        }
    }

    /// 表情の日本語表示名（デバッグ用）
    var displayName: String {
        switch self {
        case .normal:     return "通常"
        case .happy:      return "嬉しい"
        case .sleepy:     return "眠そう"
        case .surprised:  return "驚き"
        case .wink:       return "ウインク"
        case .error:      return "エラー"
        case .lowBattery: return "バッテリー低下"
        case .cleaning:   return "掃除中"
        case .charging:   return "充電中"
        }
    }
}

// MARK: - RTSP配信ステータス

/// RTSP配信の接続状態
enum StreamingStatus: String, CaseIterable, Identifiable {
    case idle         // 待機中（クライアント未接続）
    case streaming    // 配信中（クライアント接続済み）
    case error        // エラー発生

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .idle:      return "待機中"
        case .streaming: return "配信中"
        case .error:     return "エラー"
        }
    }

    var indicatorColor: Color {
        switch self {
        case .idle:      return .gray
        case .streaming: return .green
        case .error:     return .red
        }
    }
}

// MARK: - ネットワーク接続状態

/// Wi-Fiネットワークの接続状態
enum NetworkStatus: String, CaseIterable, Identifiable {
    case connected    // 接続済み
    case disconnected // 切断
    case weak         // 弱い接続

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .connected:    return "接続済み"
        case .disconnected: return "未接続"
        case .weak:         return "不安定"
        }
    }

    var indicatorColor: Color {
        switch self {
        case .connected:    return .green
        case .disconnected: return .red
        case .weak:         return .orange
        }
    }
}

// MARK: - カメラ設定

/// 映像解像度の選択肢
enum VideoResolution: String, CaseIterable, Identifiable {
    case vga   = "VGA (640×480)"
    case hd720 = "720p (1280×720)"

    var id: String { rawValue }

    var width: Int {
        switch self {
        case .vga:   return 640
        case .hd720: return 1280
        }
    }

    var height: Int {
        switch self {
        case .vga:   return 480
        case .hd720: return 720
        }
    }
}

/// フレームレートの選択肢
enum VideoFrameRate: Int, CaseIterable, Identifiable {
    case fps15 = 15
    case fps24 = 24
    case fps30 = 30

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue) fps"
    }
}

// MARK: - アプリ全体の状態を管理するViewModel

/// アプリ全体の状態を管理する Observable クラス
/// @MainActor で UI スレッドの安全性を保証
@MainActor
@Observable
final class RobotAppState {
    // MARK: - 表情・UI状態
    var currentEmotion: RobotEmotion = .normal
    var isBlinking: Bool = false

    // MARK: - 配信状態
    var streamingStatus: StreamingStatus = .idle
    var connectedClientCount: Int = 0

    // MARK: - ネットワーク状態
    var networkStatus: NetworkStatus = .connected
    var ipAddress: String = "192.168.1.100"
    var rtspPort: Int = 8554
    var ssid: String = "RobotNetwork"

    // MARK: - カメラ設定
    var resolution: VideoResolution = .hd720
    var frameRate: VideoFrameRate = .fps15

    // MARK: - システム状態
    var batteryLevel: Float = 0.85    // 0.0 ~ 1.0
    var isCharging: Bool = false
    var cpuTemperature: Float = 38.0  // ℃
    var uptimeSeconds: TimeInterval = 0

    // MARK: - デバッグ
    var isDebugMode: Bool = false

    // MARK: - Computed Properties

    /// RTSP配信URL
    var rtspURL: String {
        "rtsp://\(ipAddress):\(rtspPort)/live"
    }

    /// 稼働時間の表示用文字列
    var uptimeDisplay: String {
        let hours = Int(uptimeSeconds) / 3600
        let minutes = (Int(uptimeSeconds) % 3600) / 60
        let seconds = Int(uptimeSeconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// 現在の状態から適切な表情を自動決定
    var autoEmotion: RobotEmotion {
        // 優先度順に判定
        if networkStatus == .disconnected { return .error }
        if batteryLevel < 0.1 { return .lowBattery }
        if isCharging { return .charging }
        if streamingStatus == .streaming { return .happy }
        if streamingStatus == .error { return .error }
        return .normal
    }
}
