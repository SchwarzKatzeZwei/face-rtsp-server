// MARK: - EyeShape.swift
// お掃除ロボット顔アプリ - 目のカスタムShape定義
// iOS 18+ / Swift 6 / SwiftUI

import SwiftUI

// MARK: - 目の形状を描画するカスタムShape

/// 通常の目の形状（楕円ベース + 上下カーブ調整可能）
struct EyeShape: Shape {
    /// 目の開き具合 (0.0 = 閉じた線, 1.0 = 完全な楕円)
    var openness: CGFloat

    /// 上部のカーブ量 (正: 笑顔弧, 0: ニュートラル)
    var topCurve: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(openness, topCurve) }
        set {
            openness = newValue.first
            topCurve = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let h = rect.height
        let centerX = rect.midX
        let centerY = rect.midY

        // openness に応じて目の高さを制御
        let effectiveHeight = h * max(openness, 0.02)

        // 目を閉じている時は水平線に近づく
        let topY = centerY - effectiveHeight / 2
        let bottomY = centerY + effectiveHeight / 2

        // 笑顔弧の調整
        let topControlOffset = topCurve * effectiveHeight * 0.5

        // 左端から開始
        path.move(to: CGPoint(x: rect.minX, y: centerY))

        // 上部弧（左→右）
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: centerY),
            control: CGPoint(x: centerX, y: topY + topControlOffset)
        )

        // 下部弧（右→左）
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: centerY),
            control: CGPoint(x: centerX, y: bottomY)
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - ×印の目（エラー状態用）

/// エラー状態で使用する×印の目の形状
struct CrossEyeShape: Shape {
    var thickness: CGFloat = 0.15

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.15
        let lineWidth = rect.width * thickness

        let insetRect = rect.insetBy(dx: inset, dy: inset)

        // 左上→右下の斜線
        path.move(to: CGPoint(x: insetRect.minX, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.minX + lineWidth, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - lineWidth))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY))
        path.addLine(to: CGPoint(x: insetRect.maxX - lineWidth, y: insetRect.maxY))
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.minY + lineWidth))
        path.closeSubpath()

        // 右上→左下の斜線
        path.move(to: CGPoint(x: insetRect.maxX - lineWidth, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.minY + lineWidth))
        path.addLine(to: CGPoint(x: insetRect.minX + lineWidth, y: insetRect.maxY))
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.maxY))
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.maxY - lineWidth))
        path.closeSubpath()

        return path
    }
}

// MARK: - 目のハイライト（瞳孔内の光沢）

/// 目の中に表示するハイライト（光の反射を模倣）
struct EyeHighlight: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [
                        color,
                        color.opacity(0.0)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
    }
}

// MARK: - 単体の目コンポーネント

/// 一つの目を表現するビュー
/// emotion パラメータに基づいて形状・色・アニメーションが決定される
struct SingleEyeView: View {
    let emotion: RobotEmotion
    let isBlinking: Bool
    let isLeftEye: Bool
    let size: CGFloat

    /// ウインク時の反対側の目の開き具合
    private var effectiveOpenness: CGFloat {
        if emotion == .wink && !isLeftEye {
            // 右目を閉じる（ウインク）
            return isBlinking ? 0.0 : 0.05
        }
        return isBlinking ? 0.0 : emotion.eyeOpenness
    }

    private var effectiveCurve: CGFloat {
        if emotion == .wink && !isLeftEye {
            return 0.5  // ウインクの目は笑顔弧
        }
        return emotion.eyeCurve
    }

    private var effectiveScale: CGFloat {
        emotion.eyeScale
    }

    var body: some View {
        ZStack {
            if emotion == .error {
                // エラー時は×印
                CrossEyeShape()
                    .fill(emotion.eyeColor)
                    .frame(width: size, height: size * 0.7)
                    .scaleEffect(effectiveScale)
            } else {
                // 通常の目の形状
                EyeShape(
                    openness: effectiveOpenness,
                    topCurve: effectiveCurve
                )
                .fill(emotion.eyeColor)
                .frame(width: size, height: size * 0.7)
                .scaleEffect(effectiveScale)
                .shadow(
                    color: emotion.eyeColor.opacity(0.4),
                    radius: 15,
                    x: 0,
                    y: 0
                )

                // ハイライト（目が十分開いている時のみ）
                if effectiveOpenness > 0.3 && emotion != .error {
                    EyeHighlight(
                        size: size * 0.15,
                        color: emotion.pupilHighlightColor
                    )
                    .offset(
                        x: -size * 0.12,
                        y: -size * 0.08
                    )
                    .opacity(Double(effectiveOpenness))
                }

                // 掃除中のキラキラエフェクト
                if emotion == .cleaning {
                    SparkleEffect(size: size)
                }
            }
        }
        .animation(
            .easeInOut(duration: isBlinking ? 0.15 : 0.4),
            value: effectiveOpenness
        )
        .animation(
            .easeInOut(duration: 0.5),
            value: emotion
        )
    }
}

// MARK: - キラキラエフェクト（掃除中の装飾）

/// 掃除中に目の周りに表示されるキラキラエフェクト
struct SparkleEffect: View {
    let size: CGFloat
    @State private var sparklePhase: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let angle = (CGFloat(index) / 3.0 * .pi * 2) + sparklePhase
                let radius = size * 0.45

                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.08))
                    .foregroundStyle(.yellow)
                    .offset(
                        x: CGFloat(cos(angle)) * radius,
                        y: CGFloat(sin(angle)) * radius
                    )
                    .opacity(0.6 + 0.4 * Double(sin(sparklePhase * 3 + CGFloat(index))))
            }
        }
        .onAppear {
            withAnimation(
                .linear(duration: 4.0)
                .repeatForever(autoreverses: false)
            ) {
                sparklePhase = .pi * 2
            }
        }
    }
}

// MARK: - Preview

#Preview("目の表情一覧") {
    ScrollView {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 20) {
            ForEach(RobotEmotion.allCases) { emotion in
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.black)
                            .frame(height: 120)

                        HStack(spacing: 30) {
                            SingleEyeView(
                                emotion: emotion,
                                isBlinking: false,
                                isLeftEye: true,
                                size: 80
                            )
                            SingleEyeView(
                                emotion: emotion,
                                isBlinking: false,
                                isLeftEye: false,
                                size: 80
                            )
                        }
                    }
                    Text(emotion.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}
