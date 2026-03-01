// MARK: - RobotFaceView.swift
// お掃除ロボット顔アプリ - メイン顔表示画面
// iOS 18+ / Swift 6 / SwiftUI
//
// この画面がアプリの主画面であり、ロボットの「顔」として常時表示される。
// 黒背景に大きな目を中央配置し、瞬きや表情変化のアニメーションを行う。
// デバッグモード以外ではシステム情報は一切表示しない。
//
// preview.html の Face Display Screen を忠実に再現:
//   - .face-canvas: 黒背景 + 中央配置
//   - .eyes-container: gap 50px で左右に目を配置
//   - .mouth: 感情に応じた口（smile / surprised / hidden）
//   - .debug-overlay: 右上のデバッグ情報パネル
//   - .blinking: 4秒周期の瞬きアニメーション

import SwiftUI

// MARK: - メイン顔表示ビュー

struct RobotFaceView: View {
    @Bindable var appState: RobotAppState

    /// 瞬きタイマーの状態管理
    @State private var blinkTimer: Timer?
    @State private var isBlinking: Bool = false

    /// 表情自動切替の有効/無効（trueの場合 autoEmotion を使用）
    @State private var autoEmotionEnabled: Bool = true

    var body: some View {
        GeometryReader { geometry in
            // preview.html の比率に基づくサイズ計算:
            //   iphone-frame: 320×693
            //   eye: width 90px → 90/320 ≈ 0.28 of screen width
            //   eyes-container gap: 50px → 50/320 ≈ 0.16 of screen width
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let eyeSize = min(screenWidth, screenHeight) * 0.28
            let eyeSpacing = eyeSize * 0.55  // gap between eyes

            ZStack {
                // ── 背景: 完全な黒 ──
                // preview.html: .face-canvas background: #000
                Color.black
                    .ignoresSafeArea()

                // ── 目と口の配置 ──
                VStack(spacing: 0) {
                    Spacer()

                    // 目のコンテナ
                    // preview.html: .eyes-container { display: flex; gap: 50px; }
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

                    // ── 口の表現 ──
                    // preview.html: .mouth { margin-top: 30px }
                    switch currentEmotion.mouthType {
                    case .smile:
                        SmileMouthView(color: currentEmotion.mouthColor)
                            .frame(
                                width: eyeSize * 0.45,
                                height: eyeSize * 0.22
                            )
                            .padding(.top, eyeSize * 0.33)
                            .transition(.opacity)

                    case .surprised:
                        SurprisedMouthView()
                            .frame(
                                width: eyeSize * 0.22,
                                height: eyeSize * 0.27
                            )
                            .padding(.top, eyeSize * 0.33)
                            .transition(.opacity)

                    case .hidden:
                        // 口なし - スペーサーで高さ維持
                        Color.clear
                            .frame(height: eyeSize * 0.1)
                    }

                    Spacer()
                }

                // ── 配信状態インジケーター（画面下部） ──
                // デバッグモードでない場合もさりげなく表示
                VStack {
                    Spacer()
                    StreamingIndicator(status: appState.streamingStatus)
                        .padding(.bottom, 20)
                }

                // ── デバッグオーバーレイ ──
                // preview.html: .debug-overlay { position: absolute; top: 50px; right: 12px; }
                if appState.isDebugMode {
                    DebugOverlayView(appState: appState)
                }
            }
        }
        .onAppear {
            startBlinkLoop()
        }
        .onDisappear {
            blinkTimer?.invalidate()
        }
        .animation(.easeInOut(duration: 0.4), value: currentEmotion)
        .persistentSystemOverlays(.hidden)
    }

    // MARK: - Private

    /// 現在表示すべき表情
    private var currentEmotion: RobotEmotion {
        autoEmotionEnabled ? appState.autoEmotion : appState.currentEmotion
    }

    /// 瞬きのループを開始
    /// preview.html: @keyframes blink { 4s ease-in-out infinite }
    /// 92%~100% でまぶたの開閉 → ランダム間隔 2.5~6.0s で再現
    private func startBlinkLoop() {
        scheduleNextBlink()
    }

    /// 次の瞬きをランダムな間隔でスケジュール
    private func scheduleNextBlink() {
        let interval = TimeInterval.random(in: 2.5...6.0)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in
                performBlink()
            }
        }
    }

    /// 瞬きアニメーションを実行
    private func performBlink() {
        // エラー状態では瞬きしない（preview.html: canvas.classList.toggle('blinking', emotion !== 'error')）
        guard currentEmotion.canBlink else {
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
            scheduleNextBlink()
        }
    }
}

// MARK: - にっこり口

/// preview.html の .mouth-smile に対応:
///   width: 40px, height: 20px
///   border: 3px solid
///   border-color: transparent transparent var(--eye-cyan) transparent
///   border-radius: 0 0 50% 50%
/// → 下半分のみの弧線（笑顔の口）
struct SmileMouthView: View {
    let color: Color

    var body: some View {
        SmilePath()
            .stroke(color, lineWidth: 3)
            .opacity(0.8)
    }
}

/// 笑顔の口弧パス
struct SmilePath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // 上端の左右から始まり、下に膨らむ弧
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}

// MARK: - 驚き口

/// preview.html の .mouth-surprised に対応:
///   width: 20px, height: 24px
///   border: 2px solid rgba(255,255,255,0.5)
///   border-radius: 50%
/// → 小さな楕円（驚きの「O」の口）
struct SurprisedMouthView: View {
    var body: some View {
        Ellipse()
            .stroke(Color.white.opacity(0.5), lineWidth: 2)
    }
}

// MARK: - デバッグオーバーレイ

/// デバッグモード時に画面右上に表示するシステム情報パネル
/// preview.html の .debug-overlay に対応:
///   position: absolute; top: 50px; right: 12px;
///   background: rgba(30,30,30,0.85); backdrop-filter: blur(10px);
///   padding: 10px 14px; border-radius: 10px;
///   font-family: 'SF Mono'; font-size: 9px;
struct DebugOverlayView: View {
    let appState: RobotAppState

    var body: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    debugInfoRow("IP", appState.ipAddress)
                    debugInfoRow("RTSP", appState.rtspURL)
                    debugInfoRow("Status", appState.streamingStatus.displayName)
                    debugInfoRow("Clients", "\(appState.connectedClientCount)")
                    debugInfoRow("Resolution", appState.resolution.rawValue)
                    debugInfoRow("FPS", appState.frameRate.displayName)
                    debugInfoRow("Battery", "\(Int(appState.batteryLevel * 100))%")
                    debugInfoRow("Temp", String(format: "%.1f℃", appState.cpuTemperature))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(white: 0.12).opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.trailing, 12)
                .padding(.top, 50)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func debugInfoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.4))
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.8))
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
            .onChange(of: status) { _, newStatus in
                if newStatus == .streaming {
                    withAnimation(
                        .easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true)
                    ) {
                        isPulsing = true
                    }
                } else {
                    withAnimation {
                        isPulsing = false
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
    state.isCleaningMode = true
    return RobotFaceView(appState: state)
}

#Preview("顔表示画面 - 嬉しい(配信中)") {
    let state = RobotAppState()
    state.streamingStatus = .streaming
    return RobotFaceView(appState: state)
}

#Preview("顔表示画面 - 充電中") {
    let state = RobotAppState()
    state.isCharging = true
    return RobotFaceView(appState: state)
}

#Preview("顔表示画面 - バッテリー低下") {
    let state = RobotAppState()
    state.batteryLevel = 0.05
    return RobotFaceView(appState: state)
}
