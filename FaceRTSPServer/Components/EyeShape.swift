// MARK: - EyeShape.swift
// お掃除ロボット顔アプリ - 目のカスタムShape定義
// iOS 18+ / Swift 6 / SwiftUI
//
// preview.html の CSS に忠実なコンポーネント群:
//   - EyeShape:       通常の楕円ベースの目（openness + topCurve で形状制御）
//   - CrossEyeShape:  ×印の目（エラー状態）
//   - EyeHighlight:   大小2つのハイライト（目の光沢反射）
//   - SingleEyeView:  1つの目の完全なコンポーネント（形状+色+ハイライト+グロー）
//   - SparkleEffect:  掃除中のキラキラ回転エフェクト

import SwiftUI

// MARK: - 目の形状を描画するカスタムShape

/// 通常の目の形状（楕円ベース + 上下カーブ調整可能）
///
/// preview.html の CSS border-radius 変形を path で再現:
///   - .normal:    border-radius: 50% → 均等な楕円
///   - .happy:     50% 50% 50% 50% / 70% 70% 30% 30% → 上部が丸く下部が平坦な弧
///   - .sleepy:    border-radius: 50% → 縦に潰れた楕円
///   - .surprised: border-radius: 50% → 大きな楕円
struct EyeShape: Shape {
    /// 目の開き具合 (0.0 = 閉じた線, 1.0 = 完全な楕円)
    var openness: CGFloat

    /// 上部のカーブ量 (正: 笑顔弧で下が平坦化, 0: ニュートラル楕円)
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
        let centerX = rect.midX
        let centerY = rect.midY

        // openness に応じて目の高さを制御
        let effectiveHeight = rect.height * max(openness, 0.02)

        // 目を閉じている時は水平線に近づく
        let topY = centerY - effectiveHeight / 2
        let bottomY = centerY + effectiveHeight / 2

        // topCurve > 0 の時: 上弧を浅くし下弧を深くする（笑顔の目）
        // これにより happy/cleaning の "50% 50% 50% 50% / 70% 70% 30% 30%" を再現
        let topControlY = topY - effectiveHeight * 0.3 + (topCurve * effectiveHeight * 0.6)
        let bottomControlY = bottomY + effectiveHeight * 0.3 - (topCurve * effectiveHeight * 0.15)

        // 左端から開始
        path.move(to: CGPoint(x: rect.minX, y: centerY))

        // 上部弧（左→右）
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: centerY),
            control: CGPoint(x: centerX, y: topControlY)
        )

        // 下部弧（右→左）
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: centerY),
            control: CGPoint(x: centerX, y: bottomControlY)
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - ウインクで閉じた目の形状

/// ウインク時の閉じた目を表現する弧型 Shape
/// preview.html の .eye-wink-closed: "border-radius: 0 0 50% 50% / 0 0 100% 100%"
/// → 下半分だけの弧で「にっこり閉じた目」
struct WinkClosedEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centerY = rect.midY

        // 水平線から下に弧を描く（閉じた笑顔目）
        path.move(to: CGPoint(x: rect.minX, y: centerY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: centerY),
            control: CGPoint(x: rect.midX, y: centerY + rect.height * 0.8)
        )

        path.closeSubpath()
        return path
    }
}

// MARK: - ×印の目（エラー状態用）

/// エラー状態で使用する×印の目の形状
/// preview.html の .eye-error::before / ::after に対応:
///   幅 70px, 高さ 10px の矩形を ±45° 回転
struct CrossEyeShape: Shape {
    /// 線の太さ比率 (0.0~1.0)
    var thickness: CGFloat = 0.14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.12
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
/// preview.html の .eye-highlight + .eye-highlight-small を再現:
///   - メインハイライト: 18×18, top 15%, left 22%, opacity 0.85, blur 1px
///   - サブハイライト:    8×8,  top 45%, right 22%, opacity 0.5, blur 1px
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
            .blur(radius: 1)
    }
}

// MARK: - 単体の目コンポーネント

/// 一つの目を表現するビュー
/// emotion パラメータに基づいて形状・色・グロー・ハイライトが決定される
///
/// preview.html の各 .eye-* クラスを忠実に再現:
///   - 目の形状: EyeShape (openness + topCurve)
///   - グロー: 内側 shadow (glowColor, glowRadius) + 外側 shadow (outerGlowColor)
///   - ハイライト: メイン + サブ の2点（showsHighlight が true の感情のみ）
///   - エラー時: CrossEyeShape で ×印
///   - ウインク閉じ目: WinkClosedEyeShape
///   - 掃除中: SparkleEffect を重畳
struct SingleEyeView: View {
    let emotion: RobotEmotion
    let isBlinking: Bool
    let isLeftEye: Bool
    let size: CGFloat

    /// ウインク時の閉じた目の判定
    private var isWinkClosed: Bool {
        emotion == .wink && !isLeftEye
    }

    /// 実効的な目の開き具合（瞬き・ウインク考慮）
    private var effectiveOpenness: CGFloat {
        if isWinkClosed {
            return isBlinking ? 0.0 : 0.05
        }
        return isBlinking ? 0.0 : emotion.eyeOpenness
    }

    /// 実効的なカーブ値
    private var effectiveCurve: CGFloat {
        if isWinkClosed {
            return 0.5
        }
        return emotion.eyeCurve
    }

    /// 目のフレームサイズ
    private var eyeWidth: CGFloat {
        size * emotion.eyeScale
    }

    private var eyeHeight: CGFloat {
        size * 0.72 * emotion.eyeScale  // preview: height/width ≈ 65/90 ≈ 0.72
    }

    var body: some View {
        ZStack {
            if emotion == .error {
                // ── エラー: ×印 ──
                // preview.html: .eye-error → 透明背景 + ::before/::after で赤い×
                CrossEyeShape()
                    .fill(emotion.eyeColor)
                    .frame(width: eyeWidth, height: eyeHeight)
                    .shadow(
                        color: emotion.glowColor,
                        radius: emotion.glowRadius * 0.5,
                        x: 0, y: 0
                    )
            } else if isWinkClosed {
                // ── ウインク閉じ目 ──
                // preview.html: .eye-wink-closed → 高さ 6px, 下弧
                WinkClosedEyeShape()
                    .fill(emotion.eyeColor)
                    .frame(width: eyeWidth, height: size * 0.15)
                    .offset(y: size * 0.1)
                    .shadow(
                        color: emotion.glowColor,
                        radius: emotion.glowRadius * 0.3,
                        x: 0, y: 0
                    )
            } else {
                // ── 通常の目 ──
                // 外側グロー（二重グローの外側）
                EyeShape(
                    openness: effectiveOpenness,
                    topCurve: effectiveCurve
                )
                .fill(emotion.eyeColor)
                .frame(width: eyeWidth, height: eyeHeight)
                .shadow(
                    color: emotion.glowColor,
                    radius: emotion.glowRadius * 0.4,
                    x: 0, y: 0
                )
                .shadow(
                    color: emotion.outerGlowColor,
                    radius: emotion.glowRadius,
                    x: 0, y: 0
                )

                // ── ハイライト（目が十分開いており、かつ表情がハイライト対応の場合） ──
                if effectiveOpenness > 0.3 && emotion.showsHighlight {
                    // メインハイライト: preview の .eye-highlight
                    // 18/90 ≈ 0.2 サイズ比, top 15%, left 22%
                    EyeHighlight(
                        size: size * 0.2,
                        color: .white.opacity(0.85)
                    )
                    .offset(
                        x: -eyeWidth * 0.15,
                        y: -eyeHeight * 0.15
                    )
                    .opacity(Double(effectiveOpenness))

                    // サブハイライト: preview の .eye-highlight-small
                    // 8/90 ≈ 0.09 サイズ比, top 45%, right 22%
                    EyeHighlight(
                        size: size * 0.09,
                        color: .white.opacity(0.5)
                    )
                    .offset(
                        x: eyeWidth * 0.16,
                        y: eyeHeight * 0.05
                    )
                    .opacity(Double(effectiveOpenness))
                }

                // ── 掃除中のキラキラエフェクト ──
                if emotion.showsSparkle {
                    SparkleEffect(size: size)
                }
            }
        }
        // 瞬き時は高速アニメーション、表情遷移時はスムーズアニメーション
        .animation(
            .easeInOut(duration: isBlinking ? 0.12 : 0.4),
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
/// preview.html の .sparkles に対応:
///   - 3つの ✦ 文字を回転配置
///   - @keyframes sparkle-rotate: 6s で全体回転
///   - @keyframes sparkle-pulse: 1.5s で各スパークルが明滅
struct SparkleEffect: View {
    let size: CGFloat

    /// 全体の回転角度（0 → 2π のアニメーション）
    @State private var rotationAngle: CGFloat = 0

    /// 個々のスパークルの明滅フェーズ
    @State private var pulsePhase: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                // 各スパークルを均等角度で配置
                let baseAngle = CGFloat(index) / 3.0 * .pi * 2
                let angle = baseAngle + rotationAngle
                let radius = size * 0.55

                // パルスアニメーション: preview の animation-delay に対応
                let delayedPhase = pulsePhase + CGFloat(index) * 0.33
                let pulseOpacity = 0.4 + 0.6 * (sin(delayedPhase * .pi * 2) * 0.5 + 0.5)

                Text("\u{2726}")  // ✦ sparkle character
                    .font(.system(size: size * 0.1))
                    .foregroundStyle(Color(red: 1.0, green: 0.843, blue: 0.0)) // #ffd700
                    .offset(
                        x: cos(angle) * radius,
                        y: sin(angle) * radius
                    )
                    .opacity(pulseOpacity)
            }
        }
        .onAppear {
            // 全体回転: 6秒で1回転 (preview: sparkle-rotate 6s linear infinite)
            withAnimation(
                .linear(duration: 6.0)
                .repeatForever(autoreverses: false)
            ) {
                rotationAngle = .pi * 2
            }

            // パルス明滅: 1.5秒周期 (preview: sparkle-pulse 1.5s)
            withAnimation(
                .linear(duration: 1.5)
                .repeatForever(autoreverses: false)
            ) {
                pulsePhase = 1.0
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

#Preview("ウインク") {
    ZStack {
        Color.black.ignoresSafeArea()
        HStack(spacing: 40) {
            SingleEyeView(emotion: .wink, isBlinking: false, isLeftEye: true, size: 100)
            SingleEyeView(emotion: .wink, isBlinking: false, isLeftEye: false, size: 100)
        }
    }
}
