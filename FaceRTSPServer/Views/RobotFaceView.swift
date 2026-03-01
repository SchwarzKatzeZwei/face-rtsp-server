// MARK: - RobotFaceView.swift
// お掃除ロボット顔アプリ - メイン顔表示画面
// iOS 18+ / Swift 6 / SwiftUI
//
// この画面がアプリの主画面であり、ロボットの「顔」として常時表示される。
// 黒背景に大きな目を中央配置し、瞬きや表情変化のアニメーションを行う。
// デバッグモード以外ではシステム情報は一切表示しない。

import SwiftUI

// MARK: - メイン顔表示ビュー

struct RobotFaceView: View {
    @Bindable var appState: RobotAppState

    /// 瞬きタイマーの状態管理
    @State private var blinkTimer: Timer?
    @State private var isBlinking: Bool = false

    /// 表情自動切替の有効/無効
    @State private var autoEmotionEnabled: Bool = true

    var body: some View {
        GeometryReader { geometry in
            let eyeSize = min(geometry.size.width, geometry.size.height) * 0.40
            let eyeSpacing = eyeSize * 0.55

            ZStack {
                // ── 背景: 完全な黒 ──
                Color.black
                    .ignoresSafeArea()

                // ── 目の配置 ──
                VStack(spacing: 0) {
                    Spacer()

                    HStack(spacing: eyeSpacing) {
                        // 左目
                        SingleEyeView(
                            emotion: currentEmotion,
                            isBlinking: isBlinking,
                            isLeftEye: true,
                            size: eyeSize
                        )

                        // 右目
                        SingleEyeView(
                            emotion: currentEmotion,
                            isBlinking: isBlinking,
                            isLeftEye: false,
                            size: eyeSize
                        )
                    }

                    // 口の表現（オプション: 感情に応じた小さな弧）
                    if shouldShowMouth {
                        MouthView(emotion: currentEmotion)
                            .frame(
                                width: eyeSize * 0.4,
                                height: eyeSize * 0.12
                            )
                            .padding(.top, eyeSize * 0.25)
                    }

                    Spacer()
                }

                // ── デバッグオーバーレイ ──
                if appState.isDebugMode {
                    DebugOverlayView(appState: appState)
                }

                // ── 設定画面への隠しジェスチャー ──
                // 画面右上の角を3回タップで設定画面を開く
                // （キオスクモードでないデバッグ時のみ動作）
            }
        }
        .onAppear {
            startBlinkLoop()
        }
        .onDisappear {
            blinkTimer?.invalidate()
        }
        .persistentSystemOverlays(.hidden) // iOS 16+: システムオーバーレイを非表示
    }

    // MARK: - Private

    /// 現在表示すべき表情
    private var currentEmotion: RobotEmotion {
        autoEmotionEnabled ? appState.autoEmotion : appState.currentEmotion
    }

    /// 口を表示するかどうか
    private var shouldShowMouth: Bool {
        switch currentEmotion {
        case .happy, .cleaning, .surprised:
            return true
        default:
            return false
        }
    }

    /// 瞬きのループを開始
    private func startBlinkLoop() {
        scheduleNextBlink()
    }

    /// 次の瞬きをランダムな間隔でスケジュール
    private func scheduleNextBlink() {
        let interval = TimeInterval.random(in: 2.5...6.0)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            performBlink()
        }
    }

    /// 瞬きアニメーションを実行
    private func performBlink() {
        // エラー状態では瞬きしない
        guard currentEmotion != .error else {
            scheduleNextBlink()
            return
        }

        withAnimation(.easeInOut(duration: 0.12)) {
            isBlinking = true
        }

        // 0.15秒後に目を開く
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.12)) {
                isBlinking = false
            }
            // 次の瞬きをスケジュール
            scheduleNextBlink()
        }
    }
}

// MARK: - 口のビュー

/// 感情に応じた口の表現
struct MouthView: View {
    let emotion: RobotEmotion

    var body: some View {
        switch emotion {
        case .happy, .cleaning:
            // にっこり弧
            SmilePath()
                .stroke(emotion.eyeColor, lineWidth: 3)
                .opacity(0.7)
        case .surprised:
            // 丸い口
            Ellipse()
                .stroke(Color.white, lineWidth: 2)
                .opacity(0.5)
                .scaleEffect(x: 0.5, y: 0.6)
        default:
            EmptyView()
        }
    }
}

/// 笑顔の口弧
struct SmilePath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}

// MARK: - デバッグオーバーレイ

/// デバッグモード時に画面上に表示するシステム情報
struct DebugOverlayView: View {
    let appState: RobotAppState

    var body: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    debugInfoRow("IP", appState.ipAddress)
                    debugInfoRow("RTSP", appState.rtspURL)
                    debugInfoRow("配信", appState.streamingStatus.displayName)
                    debugInfoRow("接続数", "\(appState.connectedClientCount)")
                    debugInfoRow("Wi-Fi", appState.networkStatus.displayName)
                    debugInfoRow("解像度", appState.resolution.rawValue)
                    debugInfoRow("FPS", appState.frameRate.displayName)
                    debugInfoRow("バッテリー", "\(Int(appState.batteryLevel * 100))%")
                    debugInfoRow("温度", String(format: "%.1f℃", appState.cpuTemperature))
                    debugInfoRow("稼働時間", appState.uptimeDisplay)
                    debugInfoRow("表情", appState.autoEmotion.displayName)
                }
                .padding(12)
                .background(.ultraThinMaterial.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.trailing, 16)
                .padding(.top, 50)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func debugInfoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - 配信状態インジケーター（画面下部にさりげなく表示）

/// RTSP配信中を示す小さなドットインジケーター
struct StreamingIndicator: View {
    let status: StreamingStatus
    @State private var isPulsing: Bool = false

    var body: some View {
        Circle()
            .fill(status.indicatorColor)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(status == .idle ? 0.3 : 0.8)
            .onAppear {
                if status == .streaming {
                    withAnimation(
                        .easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true)
                    ) {
                        isPulsing = true
                    }
                }
            }
    }
}

// MARK: - Preview

#Preview("顔表示画面 - 通常") {
    let state = RobotAppState()
    RobotFaceView(appState: state)
}

#Preview("顔表示画面 - デバッグモード") {
    let state = RobotAppState()
    state.isDebugMode = true
    state.streamingStatus = .streaming
    state.connectedClientCount = 1
    return RobotFaceView(appState: state)
}

#Preview("顔表示画面 - エラー状態") {
    let state = RobotAppState()
    state.networkStatus = .disconnected
    return RobotFaceView(appState: state)
}

#Preview("顔表示画面 - 掃除中") {
    let state = RobotAppState()
    state.currentEmotion = .cleaning
    return RobotFaceView(appState: state)
}
