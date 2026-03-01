// MARK: - RTSPServer.swift
// Network.framework を使った最小 RTSP/RTP サーバー（TCP インターリーブド）
// iOS 18+ / Swift 6
//
// サポートするメソッド: OPTIONS, DESCRIBE, SETUP, PLAY, TEARDOWN
// 映像: H.264 / RTP over TCP (RFC 6184)  ポート: 8554

import Foundation
import Network
import CoreMedia
import Darwin  // getifaddrs

// MARK: - ローカル IP 取得（Network.framework が平文で取れないため BSD を使う）

private func getLocalIPv4() -> String {
    var result = "127.0.0.1"
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return result }
    defer { freeifaddrs(ifaddr) }
    var ptr = ifaddr
    while let interface = ptr {
        if interface.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
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

// MARK: - RTP 定数

private let kRTPVersion:     UInt8  = 0x80         // V=2, P=0, X=0, CC=0
private let kRTPPayloadH264: UInt8  = 96            // 動的 PT
private let kRTPClockRate:   UInt32 = 90_000        // H.264 は 90 kHz
private let kRTPMTU                 = 1390          // 1 パケットあたりの最大ペイロードサイズ
private let kRTSPVersion            = "RTSP/1.0"
private let kRTSPOK                 = "200 OK"

// MARK: - RTSPServer

/// RTSP サーバー本体。カメラキャプチャと連携して映像を配信する。
final class RTSPServer: @unchecked Sendable {

    // MARK: - Properties

    /// クライアント接続数が変化した時に呼ばれる（MainActor で呼び出す）
    var onClientCountChanged: (@Sendable (Int) -> Void)?

    /// エラー発生時に呼ばれる
    var onError: (@Sendable (String) -> Void)?

    /// SDP 生成に使うカメラキャプチャ（弱参照）
    weak var cameraCapture: CameraCapture?

    /// 居害のローカル IP
    private(set) var localIP: String = "127.0.0.1"

    // MARK: - Private

    private var listener: NWListener?
    private let serverQueue  = DispatchQueue(label: "com.robotface.rtsp.server", qos: .utility)
    private var clients      = [String: RTSPClientSession]()     // sessionID → session

    // MARK: - Public API

    func start(port: UInt16 = 8554) throws {
        localIP = getLocalIPv4()
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port) ?? NWEndpoint.Port(8554))
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] (state: NWListener.State) in
            switch state {
            case .ready:
                break
            case .failed(let err):
                self?.onError?("RTSP Listener error: \(err)")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.serverQueue.async {
                self?.accept(connection)
            }
        }

        listener.start(queue: serverQueue)
    }

    func stop() {
        serverQueue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
            self?.clients.values.forEach { $0.cancel() }
            self?.clients.removeAll()
        }
    }

    /// エンコード済みフレームを全 PLAYING クライアントに配信する
    func deliverFrame(_ nalUnits: [Data], isKeyFrame: Bool, pts: CMTime) {
        serverQueue.async { [weak self] in
            self?.clients.values.forEach { session in
                session.deliverFrame(nalUnits, isKeyFrame: isKeyFrame, pts: pts)
            }
        }
    }

    // MARK: - Connection Accept

    private func accept(_ connection: NWConnection) {
        let session = RTSPClientSession(connection: connection, serverQueue: serverQueue)
        session.server = self
        session.onClose = { [weak self, weak session] in
            guard let self, let session else { return }
            self.clients.removeValue(forKey: session.sessionID)
            self.notifyClientCount()
        }
        clients[session.sessionID] = session
        session.start()
        notifyClientCount()
    }

    // MARK: - SDP 生成

    func buildSDP(localIP: String) -> String {
        let spsBase64 = cameraCapture?.spsData.map { $0.base64EncodedString() } ?? ""
        let ppsBase64 = cameraCapture?.ppsData.map { $0.base64EncodedString() } ?? ""

        // profile-level-id を SPS から抽出（なければ Baseline 3.1 のデフォルト）
        var profileLevelID = "42e01f"
        if let sps = cameraCapture?.spsData, sps.count >= 4 {
            profileLevelID = String(format: "%02x%02x%02x", sps[1], sps[2], sps[3])
        }

        var fmtp = "packetization-mode=1;profile-level-id=\(profileLevelID)"
        if !spsBase64.isEmpty, !ppsBase64.isEmpty {
            fmtp += ";sprop-parameter-sets=\(spsBase64),\(ppsBase64)"
        }

        let sdp = """
        v=0\r
        o=- 0 0 IN IP4 \(localIP)\r
        s=RobotFace Live\r
        c=IN IP4 \(localIP)\r
        t=0 0\r
        m=video 0 RTP/AVP 96\r
        a=rtpmap:96 H264/90000\r
        a=fmtp:96 \(fmtp)\r
        a=control:track1\r
        \r

        """
        return sdp
    }

    // MARK: - Helpers

    private func notifyClientCount() {
        let count = clients.values.filter { $0.isPlaying }.count
        let cb = onClientCountChanged
        DispatchQueue.main.async { cb?(count) }
    }
}

// MARK: - RTSPClientSession

/// 1 クライアントの RTSP ステートマシンと RTP 配信を管理
final class RTSPClientSession: @unchecked Sendable {

    // MARK: - RTSP State

    enum RTSPState { case initial, ready, playing }

    // MARK: - Properties

    let sessionID: String
    private let connection: NWConnection
    private let queue: DispatchQueue

    private var state: RTSPState = .initial
    private var receiveBuffer = Data()

    // RTP
    private var rtpSeqNum: UInt16 = UInt16.random(in: 0...UInt16.max)
    private let rtpSSRC: UInt32   = UInt32.random(in: 0...UInt32.max)

    weak var server: RTSPServer?
    var onClose: (() -> Void)?

    var isPlaying: Bool { state == .playing }

    // MARK: - Init

    init(connection: NWConnection, serverQueue: DispatchQueue) {
        self.connection = connection
        self.queue      = serverQueue
        self.sessionID  = String(format: "%08X", UInt32.random(in: 0...UInt32.max))
    }

    // MARK: - Lifecycle

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.onClose?()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveNext()
    }

    func cancel() {
        connection.cancel()
    }

    // MARK: - Receive Loop

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            if let data = content { self.receiveBuffer.append(data) }
            self.processBuffer()
            if isComplete || error != nil {
                self.onClose?()
            } else {
                self.receiveNext()
            }
        }
    }

    private func processBuffer() {
        // RTSP メッセージは \r\n\r\n で終端
        while let range = receiveBuffer.range(of: Data("\r\n\r\n".utf8)) {
            let messageData = receiveBuffer[..<range.upperBound]
            receiveBuffer.removeSubrange(..<range.upperBound)
            if let message = String(data: messageData, encoding: .utf8) {
                handleRTSPMessage(message)
            }
        }
    }

    // MARK: - RTSP Message Handling

    private func handleRTSPMessage(_ message: String) {
        let lines = message.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }

        let method = parts[0]
        let cseq   = extractHeader("CSeq", from: lines) ?? "0"

        switch method {
        case "OPTIONS":
            send(rtspResponse(cseq: cseq, extra: "Public: OPTIONS, DESCRIBE, SETUP, PLAY, TEARDOWN\r\n"))

        case "DESCRIBE":
            let sdp  = server?.buildSDP(localIP: server?.localIP ?? "127.0.0.1") ?? ""
            let body = sdp.data(using: .utf8) ?? Data()
            let extra = "Content-Type: application/sdp\r\nContent-Length: \(body.count)\r\n\r\n"
            var response = "\(kRTSPVersion) \(kRTSPOK)\r\nCSeq: \(cseq)\r\n\(extra)"
            response += sdp
            sendRaw(Data(response.utf8))

        case "SETUP":
            // TCP インターリーブドのみサポート
            state = .ready
            let transport = "RTP/AVP/TCP;unicast;interleaved=0-1"
            let extra = "Session: \(sessionID)\r\nTransport: \(transport)\r\n"
            send(rtspResponse(cseq: cseq, extra: extra))

        case "PLAY":
            state = .playing
            let extra = "Session: \(sessionID)\r\nRTP-Info: url=rtsp://localhost:8554/live/track1;seq=\(rtpSeqNum);rtptime=0\r\n"
            send(rtspResponse(cseq: cseq, extra: extra))
            // 接続数通知は server 側が onClose コールバックで管理

        case "TEARDOWN":
            send(rtspResponse(cseq: cseq, extra: "Session: \(sessionID)\r\n"))
            state = .initial
            connection.cancel()

        default:
            sendRaw(Data("\(kRTSPVersion) 501 Not Implemented\r\nCSeq: \(cseq)\r\n\r\n".utf8))
        }
    }

    // MARK: - RTSP Response Helpers

    private func rtspResponse(cseq: String, extra: String) -> Data {
        let headers = "\(kRTSPVersion) \(kRTSPOK)\r\nCSeq: \(cseq)\r\n\(extra)\r\n"
        return Data(headers.utf8)
    }

    private func send(_ data: Data) {
        sendRaw(data)
    }

    private func sendRaw(_ data: Data) {
        connection.send(content: data, completion: .idempotent)
    }

    private func extractHeader(_ name: String, from lines: [String]) -> String? {
        let prefix = name + ": "
        return lines.first(where: { $0.hasPrefix(prefix) })?.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - RTP フレーム配信

    func deliverFrame(_ nalUnits: [Data], isKeyFrame: Bool, pts: CMTime) {
        guard state == .playing else { return }

        // PTS を 90 kHz タイムスタンプに変換
        let rtpTs = UInt32(truncatingIfNeeded: Int64(CMTimeGetSeconds(pts) * Double(kRTPClockRate)))

        for (idx, nalu) in nalUnits.enumerated() {
            let isLast = (idx == nalUnits.count - 1)
            sendRTPNALU(nalu, timestamp: rtpTs, marker: isLast)
        }
    }

    private func sendRTPNALU(_ nalu: Data, timestamp: UInt32, marker: Bool) {
        guard !nalu.isEmpty else { return }

        if nalu.count <= kRTPMTU {
            // ── シングル NALU パケット ────────────────────────────────────
            var packet = makeRTPHeader(marker: marker, timestamp: timestamp)
            packet.append(nalu)
            sendInterleaved(channel: 0, data: packet)
        } else {
            // ── FU-A フラグメンテーション（RFC 6184 §5.8）──────────────────
            let naluType    = nalu[0] & 0x1F
            let fuIndicator = (nalu[0] & 0xE0) | 28  // FU-A type = 28
            var offset      = 1  // NAL ヘッダをスキップ

            while offset < nalu.count {
                let remaining   = nalu.count - offset
                let chunkSize   = min(remaining, kRTPMTU - 2)  // FU indicator + FU header
                let isStart     = (offset == 1)
                let isEnd       = (offset + chunkSize >= nalu.count)

                var fuHeader: UInt8 = naluType
                if isStart { fuHeader |= 0x80 }
                if isEnd   { fuHeader |= 0x40 }

                var packet = makeRTPHeader(marker: isEnd && marker, timestamp: timestamp)
                packet.append(fuIndicator)
                packet.append(fuHeader)
                packet.append(nalu[offset ..< offset + chunkSize])
                sendInterleaved(channel: 0, data: packet)

                offset += chunkSize
            }
        }
    }

    // MARK: - RTP ヘッダ生成（12 バイト）

    private func makeRTPHeader(marker: Bool, timestamp: UInt32) -> Data {
        var header = Data(count: 12)

        header[0] = kRTPVersion
        header[1] = kRTPPayloadH264 | (marker ? 0x80 : 0x00)

        // シーケンス番号（big-endian）
        rtpSeqNum = rtpSeqNum &+ 1
        header[2] = UInt8(rtpSeqNum >> 8)
        header[3] = UInt8(rtpSeqNum & 0xFF)

        // タイムスタンプ（big-endian）
        header[4] = UInt8((timestamp >> 24) & 0xFF)
        header[5] = UInt8((timestamp >> 16) & 0xFF)
        header[6] = UInt8((timestamp >> 8)  & 0xFF)
        header[7] = UInt8( timestamp        & 0xFF)

        // SSRC（big-endian）
        header[8]  = UInt8((rtpSSRC >> 24) & 0xFF)
        header[9]  = UInt8((rtpSSRC >> 16) & 0xFF)
        header[10] = UInt8((rtpSSRC >> 8)  & 0xFF)
        header[11] = UInt8( rtpSSRC        & 0xFF)

        return header
    }

    // MARK: - インターリーブド TCP 送信

    /// RTSP over TCP インターリーブドフォーマット: $ + channel + length(2 bytes BE) + data
    private func sendInterleaved(channel: UInt8, data: Data) {
        var frame = Data(count: 4 + data.count)
        frame[0] = 0x24     // '$'
        frame[1] = channel
        frame[2] = UInt8((data.count >> 8) & 0xFF)
        frame[3] = UInt8( data.count       & 0xFF)
        frame.replaceSubrange(4..., with: data)
        sendRaw(frame)
    }
}
