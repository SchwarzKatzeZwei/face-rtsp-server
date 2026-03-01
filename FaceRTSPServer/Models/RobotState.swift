// MARK: - RobotState.swift
// お掃除ロボット顔アプリ - 状態管理モデル
// iOS 18+ / Swift 6 / SwiftUI

import SwiftUI
import Darwin
import AVFoundation

// MARK: - 口の表示タイプ

/// 口の描画パターン
enum MouthType {
    case hidden     // 口を表示しない
    case smile      // にっこり弧
    case surprised  // 丸い口
}

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
        case .normal:     return 0.72   // preview: height 65/90 ≈ 0.72
        case .happy:      return 0.72   // 弧の形なので openness は同等、topCurve で形状変更
        case .sleepy:     return 0.28   // preview: height 25/90 ≈ 0.28
        case .surprised:  return 0.76   // preview: height 80/105 ≈ 0.76
        case .wink:       return 0.72   // 開いている方の目
        case .error:      return 0.7    // ×印のため参考値
        case .lowBattery: return 0.22   // preview: height 20/90 ≈ 0.22
        case .cleaning:   return 0.72   // happy と同等の弧
        case .charging:   return 0.33   // preview: height 30/90 ≈ 0.33
        }
    }

    /// 目のサイズスケール (1.0 が基準)
    var eyeScale: CGFloat {
        switch self {
        case .normal:     return 1.0
        case .happy:      return 1.0
        case .sleepy:     return 1.0
        case .surprised:  return 1.17   // preview: 105/90 ≈ 1.17
        case .wink:       return 1.0
        case .error:      return 0.89   // preview: 80/90 ≈ 0.89
        case .lowBattery: return 1.0
        case .cleaning:   return 1.0
        case .charging:   return 1.0
        }
    }

    /// 目の色
    var eyeColor: Color {
        switch self {
        case .normal:     return .white                                      // --eye-white: #ffffff
        case .happy:      return Color(red: 0, green: 0.898, blue: 1.0)     // --eye-cyan: #00e5ff
        case .sleepy:     return Color(white: 0.69)                          // --eye-gray: #b0b0b0
        case .surprised:  return .white                                      // --eye-white: #ffffff
        case .wink:       return Color(red: 0, green: 0.898, blue: 1.0)     // --eye-cyan: #00e5ff
        case .error:      return Color(red: 0.957, green: 0.263, blue: 0.212) // --eye-red: #f44336
        case .lowBattery: return Color(red: 1.0, green: 0.596, blue: 0.0)   // --eye-orange: #ff9800
        case .cleaning:   return Color(red: 0.298, green: 0.686, blue: 0.314) // --eye-green: #4caf50
        case .charging:   return Color(red: 0.4, green: 0.8, blue: 1.0)     // --eye-blue: #66ccff
        }
    }

    /// 目のグロー（光彩）色 - preview の box-shadow に対応
    var glowColor: Color {
        switch self {
        case .normal:     return .white.opacity(0.3)
        case .happy:      return Color(red: 0, green: 0.898, blue: 1.0).opacity(0.4)
        case .sleepy:     return Color(white: 0.69).opacity(0.2)
        case .surprised:  return .white.opacity(0.4)
        case .wink:       return Color(red: 0, green: 0.898, blue: 1.0).opacity(0.4)
        case .error:      return Color(red: 0.957, green: 0.263, blue: 0.212).opacity(0.5)
        case .lowBattery: return Color(red: 1.0, green: 0.596, blue: 0.0).opacity(0.3)
        case .cleaning:   return Color(red: 0.298, green: 0.686, blue: 0.314).opacity(0.4)
        case .charging:   return Color(red: 0.4, green: 0.8, blue: 1.0).opacity(0.3)
        }
    }

    /// 目のグロー半径 - preview の box-shadow blur に対応
    var glowRadius: CGFloat {
        switch self {
        case .normal:     return 30
        case .happy:      return 30
        case .sleepy:     return 20
        case .surprised:  return 40
        case .wink:       return 30
        case .error:      return 20
        case .lowBattery: return 20
        case .cleaning:   return 30
        case .charging:   return 25
        }
    }

    /// 外側の二重グロー色 - preview の box-shadow 2番目の値に対応
    var outerGlowColor: Color {
        switch self {
        case .normal:     return .white.opacity(0.1)
        case .happy:      return Color(red: 0, green: 0.898, blue: 1.0).opacity(0.15)
        case .sleepy:     return .clear
        case .surprised:  return .white.opacity(0.15)
        case .wink:       return Color(red: 0, green: 0.898, blue: 1.0).opacity(0.15)
        case .error:      return .clear
        case .lowBattery: return .clear
        case .cleaning:   return Color(red: 0.298, green: 0.686, blue: 0.314).opacity(0.15)
        case .charging:   return .clear
        }
    }

    /// 瞳孔（ハイライト）を表示するかどうか
    var showsHighlight: Bool {
        switch self {
        case .normal, .surprised, .wink:
            return true
        default:
            return false
        }
    }

    /// 目のカーブ方向 (正: 笑顔弧, 0: ニュートラル, 負: 悲しい弧)
    var eyeCurve: CGFloat {
        switch self {
        case .happy:                     return 0.5    // 弧形の笑顔 (70% 70% 30% 30%)
        case .cleaning:                  return 0.4    // やや弧 (60% 60% 40% 40%)
        case .charging:                  return 0.15   // 穏やかな弧
        case .sleepy, .lowBattery:       return -0.05  // ほぼニュートラルだがやや下がり気味
        default:                         return 0.0
        }
    }

    /// 口の表示タイプ
    var mouthType: MouthType {
        switch self {
        case .happy:      return .smile
        case .cleaning:   return .smile
        case .surprised:  return .surprised
        default:          return .hidden
        }
    }

    /// 口の色（smile 時のストローク色）
    var mouthColor: Color {
        switch self {
        case .happy:    return Color(red: 0, green: 0.898, blue: 1.0)    // cyan
        case .cleaning: return Color(red: 0.298, green: 0.686, blue: 0.314) // green
        default:        return .white.opacity(0.5)
        }
    }

    /// 瞬きを行うかどうか（エラー時は瞬きなし）
    var canBlink: Bool {
        self != .error
    }

    /// キラキラエフェクトを表示するかどうか
    var showsSparkle: Bool {
        self == .cleaning
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

// MARK: - ローカルIPアドレス取得

/// デバイスのWi-Fi (en0) IPv4アドレスを返す。取得できない場合は "0.0.0.0"
private func getLocalIPAddress() -> String {
    var result = "0.0.0.0"
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return result }
    defer { freeifaddrs(ifaddr) }
    var ptr = ifaddr
    while let interface = ptr {
        let family = interface.pointee.ifa_addr.pointee.sa_family
        if family == UInt8(AF_INET) {
            let name = String(cString: interface.pointee.ifa_name)
            if name == "en0" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    interface.pointee.ifa_addr,
                    socklen_t(interface.pointee.ifa_addr.pointee.sa_len),
                    &hostname, socklen_t(hostname.count),
                    nil, 0, NI_NUMERICHOST
                )
                result = String(cString: hostname)
            }
        }
        ptr = interface.pointee.ifa_next
    }
    return result
}

// MARK: - アプリ全体の状態を管理するViewModel

/// アプリ全体の状態を管理する Observable クラス
/// @MainActor で UI スレッドの安全性を保証
@MainActor @Observable
final class RobotAppState {
    // MARK: - 表情・UI状態
    var currentEmotion: RobotEmotion = .normal
    var isBlinking: Bool = false

    // MARK: - 配信状態
    var streamingStatus: StreamingStatus = .idle
    var connectedClientCount: Int = 0

    // MARK: - ネットワーク状態
    var networkStatus: NetworkStatus = .connected
    var ipAddress: String = getLocalIPAddress()
    var rtspPort: Int = 8554
    var ssid: String = "---"

    // MARK: - カメラ設定
    var resolution: VideoResolution = .hd720
    var frameRate: VideoFrameRate = .fps15

    // MARK: - システム状態
    var batteryLevel: Float = 0.85    // 0.0 ~ 1.0
    var isCharging: Bool = false
    var cpuTemperature: Float = 38.0  // ℃
    var uptimeSeconds: TimeInterval = 0

    // MARK: - 表示設定
    var isDebugMode: Bool = false
    var isCleaningMode: Bool = false

    // MARK: - 一時的な表情（ウインク等）
    /// ウインクなど一時的な表情の表示フラグ
    var isShowingMomentaryEmotion: Bool = false
    /// 一時的な表情の種類
    var momentaryEmotion: RobotEmotion = .wink

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
    /// plan.md のステートマシン優先度順に判定:
    ///   1. ネットワーク切断 → error
    ///   2. バッテリー低下 → lowBattery
    ///   3. 充電中 → charging
    ///   4. 掃除モード → cleaning
    ///   5. 配信中 → happy
    ///   6. 配信エラー → error
    ///   7. デフォルト → normal
    var autoEmotion: RobotEmotion {
        // 一時的な表情（ウインク等）が表示中ならそちらを優先
        if isShowingMomentaryEmotion {
            return momentaryEmotion
        }

        // 優先度順に判定
        if networkStatus == .disconnected { return .error }
        if batteryLevel < 0.1 { return .lowBattery }
        if isCharging { return .charging }
        if isCleaningMode { return .cleaning }
        if streamingStatus == .streaming { return .happy }
        if streamingStatus == .error { return .error }
        return .normal
    }

    // MARK: - Actions

    /// RTSPクライアント接続時にウインクを一瞬表示してから happy に遷移
    /// plan.md: "RTSP client connects ---> .wink (momentary) ---> .happy"
    func triggerWinkOnConnect() {
        isShowingMomentaryEmotion = true
        momentaryEmotion = .wink

        // 1.5秒後にウインクを解除 → autoEmotion が .happy に戻る
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.isShowingMomentaryEmotion = false
        }
    }

    /// アプリの稼働時間を更新するためのタイマー開始
    private var uptimeTimer: Timer?

    func startUptimeTracking() {
        uptimeTimer?.invalidate()
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.uptimeSeconds += 1
            }
        }
    }

    func stopUptimeTracking() {
        uptimeTimer?.invalidate()
        uptimeTimer = nil
    }

    // MARK: - RTSP サーバー管理

    private let cameraCapture = CameraCapture()
    private let rtspServer    = RTSPServer()

    /// カメラキャプチャ + RTSP サーバーを起動する
    /// onAppear から呼ぶ
    func startStreaming() {
        // IP アドレスを最新化
        ipAddress = getLocalIPAddress()

        // RTSPServer に CameraCapture を渡し、コールバックを設定
        rtspServer.cameraCapture = cameraCapture

        rtspServer.onClientCountChanged = { [weak self] count in
            guard let self else { return }
            let newCount = count
            Task { @MainActor [weak self] in
                guard let self else { return }
                let prev = self.connectedClientCount
                self.connectedClientCount = newCount
                if newCount > prev {
                    self.triggerWinkOnConnect()
                }
                self.streamingStatus = newCount > 0 ? .streaming : .idle
            }
        }

        rtspServer.onError = { [weak self] msg in
            Task { @MainActor [weak self] in
                self?.streamingStatus = .error
            }
        }

        // エンコード済みフレームを RTSP サーバーに転送
        cameraCapture.onEncodedFrame = { [weak self] nalUnits, isKeyFrame, pts in
            self?.rtspServer.deliverFrame(nalUnits, isKeyFrame: isKeyFrame, pts: pts)
        }

        // カメラ設定 → RTSP サーバー起動
        Task {
            do {
                try await cameraCapture.configure(resolution: resolution, frameRate: frameRate)
                try rtspServer.start(port: UInt16(rtspPort))
                cameraCapture.start()
                await MainActor.run { self.streamingStatus = .idle }
            } catch {
                await MainActor.run { self.streamingStatus = .error }
            }
        }
    }

    func stopStreaming() {
        cameraCapture.stop()
        rtspServer.stop()
        streamingStatus = .idle
        connectedClientCount = 0
    }
}
