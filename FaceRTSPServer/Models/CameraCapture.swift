// MARK: - CameraCapture.swift
// AVFoundation + VideoToolbox によるカメラキャプチャ & H.264 エンコード
// iOS 18+ / Swift 6

import AVFoundation
import VideoToolbox
import CoreMedia
import UIKit

// MARK: - エラー定義

enum CameraError: LocalizedError {
    case permissionDenied
    case deviceNotFound
    case sessionSetupFailed(String)
    case encoderSetupFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:              return "カメラへのアクセスが拒否されました"
        case .deviceNotFound:               return "フロントカメラが見つかりません"
        case .sessionSetupFailed(let msg):  return "セッションのセットアップに失敗: \(msg)"
        case .encoderSetupFailed(let s):    return "エンコーダーの作成に失敗: \(s)"
        }
    }
}

// MARK: - エンコード済みフレームのコールバック型

/// H.264 NAL ユニットのリストを受け取るコールバック
/// - nalUnits: SPS/PPS を先頭に含む（IDR フレームの場合）
/// - isKeyFrame: IDR フレームかどうか
/// - pts: プレゼンテーションタイムスタンプ
typealias EncodedFrameCallback = @Sendable (_ nalUnits: [Data], _ isKeyFrame: Bool, _ pts: CMTime) -> Void

// MARK: - CameraCapture

/// カメラキャプチャと H.264 エンコードを管理するクラス
/// カメラスレッド上で完結し、@MainActor には依存しない
final class CameraCapture: NSObject, @unchecked Sendable {

    // MARK: - Properties

    private var captureSession: AVCaptureSession?
    private var compressionSession: VTCompressionSession?

    /// エンコード済みフレームの通知先
    var onEncodedFrame: EncodedFrameCallback?

    /// DESCRIBE レスポンス用 SPS/PPS（初回 IDR フレーム受信後に更新）
    private(set) var spsData: Data?
    private(set) var ppsData: Data?

    private var targetWidth: Int32  = 1280
    private var targetHeight: Int32 = 720
    private var targetFPS: Int32    = 15

    // カメラスレッドとエンコーダースレッドを分離
    private let captureQueue = DispatchQueue(label: "com.robotface.capture", qos: .userInteractive)
    private let encodeQueue  = DispatchQueue(label: "com.robotface.encode",  qos: .userInteractive)

    // MARK: - Public API

    /// カメラ権限要求 → セッション / エンコーダー初期化
    func configure(resolution: VideoResolution, frameRate: VideoFrameRate) async throws {
        targetWidth  = Int32(resolution.width)
        targetHeight = Int32(resolution.height)
        targetFPS    = Int32(frameRate.rawValue)

        // ── 1. カメラ権限 ──────────────────────────────────────────────────
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw CameraError.permissionDenied }
        case .authorized:
            break
        default:
            throw CameraError.permissionDenied
        }

        // ── 2. セッション / エンコーダーをキャプチャキューで初期化 ──────────
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            captureQueue.async { [weak self] in
                guard let self else { return }
                do {
                    try self.setupCaptureSession()
                    try self.setupEncoder()
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func start() {
        captureQueue.async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    func stop() {
        captureQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
        encodeQueue.async { [weak self] in
            if let session = self?.compressionSession {
                VTCompressionSessionInvalidate(session)
            }
            self?.compressionSession = nil
        }
    }

    // MARK: - Private: Session Setup

    private func setupCaptureSession() throws {
        let session = AVCaptureSession()
        session.beginConfiguration()

        // 解像度プリセット
        session.sessionPreset = (targetWidth >= 1280) ? .hd1280x720 : .vga640x480

        // フロントカメラ
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front
        ) else {
            session.commitConfiguration()
            throw CameraError.deviceNotFound
        }

        // フレームレート
        if let range = device.activeFormat.videoSupportedFrameRateRanges.first(where: {
            $0.maxFrameRate >= Double(targetFPS)
        }) {
            _ = range // suppress warning
            try device.lockForConfiguration()
            let dur = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.activeVideoMinFrameDuration = dur
            device.activeVideoMaxFrameDuration = dur
            device.unlockForConfiguration()
        }

        // 入力
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.sessionSetupFailed("入力デバイスを追加できません")
        }
        session.addInput(input)

        // 出力（YUV バッファを受け取る）
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CameraError.sessionSetupFailed("ビデオ出力を追加できません")
        }
        session.addOutput(output)

        // 横画面（デフォルト 0°）でそのまま送るため回転なし
        // エンコーダーの width/height (1280×720) と一致させる

        session.commitConfiguration()
        captureSession = session
    }

    // MARK: - Private: Encoder Setup

    private func setupEncoder() throws {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: targetWidth,
            height: targetHeight,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: compressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        guard status == noErr, let session else {
            throw CameraError.encoderSetupFailed(status)
        }

        // リアルタイム・低遅延設定
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime,            value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,         value: kVTProfileLevel_H264_Baseline_3_1)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_H264EntropyMode,      value: kVTH264EntropyMode_CABAC)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,  value: NSNumber(value: targetFPS * 2))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate,    value: NSNumber(value: targetFPS))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,       value: NSNumber(value: 1_500_000))

        VTCompressionSessionPrepareToEncodeFrames(session)
        compressionSession = session
    }

    // MARK: - Encoded Frame Handler (called from compression callback)

    func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // キーフレーム判定
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let notSync   = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        let isKeyFrame = !notSync

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // キーフレームの場合は SPS/PPS を抽出
        if isKeyFrame, let fmt = CMSampleBufferGetFormatDescription(sampleBuffer) {
            extractSPSPPS(from: fmt)
        }

        // AVCC → NAL ユニット列に変換
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var dataLength = 0
        var dataPointer: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &dataLength,
            dataPointerOut: &dataPointer
        ) == kCMBlockBufferNoErr, let dataPointer else { return }

        var nalUnits: [Data] = []

        // IDR の前に SPS/PPS を付加
        if isKeyFrame {
            if let sps = spsData { nalUnits.append(sps) }
            if let pps = ppsData { nalUnits.append(pps) }
        }

        // 4 バイト長プレフィックス（big-endian）で区切られた NAL ユニットを解析
        var offset = 0
        while offset + 4 <= dataLength {
            let b0 = UInt32(UInt8(bitPattern: dataPointer[offset]))
            let b1 = UInt32(UInt8(bitPattern: dataPointer[offset + 1]))
            let b2 = UInt32(UInt8(bitPattern: dataPointer[offset + 2]))
            let b3 = UInt32(UInt8(bitPattern: dataPointer[offset + 3]))
            let naluLen = Int((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
            offset += 4
            guard naluLen > 0, offset + naluLen <= dataLength else { break }
            nalUnits.append(Data(bytes: dataPointer.advanced(by: offset), count: naluLen))
            offset += naluLen
        }

        onEncodedFrame?(nalUnits, isKeyFrame, pts)
    }

    // MARK: - SPS/PPS Extraction

    private func extractSPSPPS(from formatDesc: CMFormatDescription) {
        var paramCount = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDesc,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &paramCount,
            nalUnitHeaderLengthOut: nil
        )
        guard paramCount >= 2 else { return }

        // SPS (index 0)
        var spsPtr: UnsafePointer<UInt8>?
        var spsLen = 0
        if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDesc, parameterSetIndex: 0,
            parameterSetPointerOut: &spsPtr, parameterSetSizeOut: &spsLen,
            parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil
        ) == noErr, let spsPtr {
            spsData = Data(bytes: spsPtr, count: spsLen)
        }

        // PPS (index 1)
        var ppsPtr: UnsafePointer<UInt8>?
        var ppsLen = 0
        if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDesc, parameterSetIndex: 1,
            parameterSetPointerOut: &ppsPtr, parameterSetSizeOut: &ppsLen,
            parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil
        ) == noErr, let ppsPtr {
            ppsData = Data(bytes: ppsPtr, count: ppsLen)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let compressionSession,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let pts      = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)

        VTCompressionSessionEncodeFrame(
            compressionSession,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }
}

// MARK: - VideoToolbox 圧縮コールバック（グローバル関数）

private func compressionOutputCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard status == noErr,
          let sampleBuffer,
          let refCon = outputCallbackRefCon,
          CMSampleBufferDataIsReady(sampleBuffer) else { return }

    // infoFlags に kVTEncodeInfo_FrameDropped が含まれる場合はスキップ
    guard !infoFlags.contains(.frameDropped) else { return }

    let camera = Unmanaged<CameraCapture>.fromOpaque(refCon).takeUnretainedValue()
    camera.handleEncodedSampleBuffer(sampleBuffer)
}
