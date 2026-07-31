//
//  LocalMediaServer.swift
//  Infra
//
//  ローカル動画ファイルを LAN 上で HTTP 配信する簡易サーバ。
//
//  Chromecast はローカル（PhotoKit）動画を直接読めず、HTTP(S) で取得できる URL を要求する。
//  そこで端末上で動く HTTP サーバを立て、書き出し済みファイルを `http://<LAN IP>:<port>/<token>` で
//  配信する。プロセス外依存（ソケット / ネットワーク）との I/O はこの Client に閉じ込める。
//
//  - Range リクエスト（部分取得）に対応し、Chromecast のシーク・バッファリングを成立させる。
//  - 配信は登録されたファイルに限定する（任意パスへのアクセスは返さない）。
//

import Foundation
import Network

/// ローカルファイルを HTTP 配信する単一責務の Client。
///
/// `start()` で待受を開始し、`register(fileURL:mimeType:)` でファイルを登録すると、デバイスが
/// 取得可能な配信 URL を返す。SDK や上位の都合（どのアセットか等）は持たず、ファイル配信だけを担う。
public final class LocalMediaServer: @unchecked Sendable {

    private let queue = DispatchQueue(label: "stotic-dev.CasualVideo.LocalMediaServer")
    private var listener: NWListener?
    private var port: UInt16?

    /// 配信対象。token をキーに、ファイル URL と MIME タイプを保持する。
    private var routes: [String: (fileURL: URL, mimeType: String)] = [:]
    private let lock = NSLock()

    public init() {}

    /// HTTP 待受を開始する（多重起動は無視）。
    public func start() {
        queue.async { [weak self] in
            guard let self, self.listener == nil else { return }
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            guard let listener = try? NWListener(using: parameters) else { return }
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                if case .ready = state {
                    self.lock.lock()
                    self.port = listener.port?.rawValue
                    self.lock.unlock()
                }
            }
            listener.start(queue: self.queue)
        }
    }

    /// ファイルを配信対象に登録し、デバイスが取得できる配信 URL を返す。
    ///
    /// 待受ポートが未確定（start 直後）の場合は確定まで短く待つ。LAN IP を取得できない／
    /// ポートが立たない場合は nil。
    public func register(fileURL: URL, mimeType: String) -> URL? {
        // ポート確定を待つ（start 直後の取りこぼし回避）。
        let resolvedPort = waitForPort()
        guard let resolvedPort, let host = Self.lanIPAddress() else { return nil }

        let token = UUID().uuidString
        lock.lock()
        routes[token] = (fileURL, mimeType)
        lock.unlock()

        return URL(string: "http://\(host):\(resolvedPort)/\(token)")
    }

    /// 登録済みの配信対象をすべて解除する（セッション終了時など）。
    public func reset() {
        lock.lock()
        routes.removeAll()
        lock.unlock()
    }

    // MARK: - Private

    private func waitForPort() -> UInt16? {
        for _ in 0..<50 {
            lock.lock()
            let current = port
            lock.unlock()
            if let current { return current }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data { buffer.append(data) }

            // ヘッダ終端（CRLFCRLF）まで読めたらリクエストを処理する。
            if let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: buffer.startIndex..<headerRange.lowerBound)
                self.respond(to: headerData, on: connection)
                return
            }
            if error != nil || isComplete {
                connection.cancel()
                return
            }
            self.receiveRequest(on: connection, accumulated: buffer)
        }
    }

    private func respond(to headerData: Data, on connection: NWConnection) {
        guard let header = String(data: headerData, encoding: .utf8) else {
            close(connection)
            return
        }
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            close(connection)
            return
        }
        let components = requestLine.components(separatedBy: " ")
        guard components.count >= 2 else {
            close(connection)
            return
        }
        let method = components[0]
        let path = components[1].hasPrefix("/") ? String(components[1].dropFirst()) : components[1]

        lock.lock()
        let route = routes[path]
        lock.unlock()

        guard let route,
              let fileData = try? Data(contentsOf: route.fileURL, options: .mappedIfSafe)
        else {
            send(statusLine: "HTTP/1.1 404 Not Found", headers: ["Content-Length": "0"], body: nil, on: connection)
            return
        }

        let totalLength = fileData.count
        // Range ヘッダがあれば部分応答（206）を返す。Chromecast のシーク・バッファに必要。
        if let rangeHeader = lines.first(where: { $0.lowercased().hasPrefix("range:") }),
           let range = Self.parseRange(rangeHeader, totalLength: totalLength) {
            let slice = fileData.subdata(in: range)
            let headers = [
                "Content-Type": route.mimeType,
                "Content-Length": "\(slice.count)",
                "Content-Range": "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(totalLength)",
                "Accept-Ranges": "bytes"
            ]
            // HEAD はボディを返さない。
            send(statusLine: "HTTP/1.1 206 Partial Content", headers: headers, body: method == "HEAD" ? nil : slice, on: connection)
            return
        }

        let headers = [
            "Content-Type": route.mimeType,
            "Content-Length": "\(totalLength)",
            "Accept-Ranges": "bytes"
        ]
        send(statusLine: "HTTP/1.1 200 OK", headers: headers, body: method == "HEAD" ? nil : fileData, on: connection)
    }

    private func send(statusLine: String, headers: [String: String], body: Data?, on connection: NWConnection) {
        var head = statusLine + "\r\n"
        for (key, value) in headers {
            head += "\(key): \(value)\r\n"
        }
        head += "Connection: close\r\n\r\n"

        var response = Data(head.utf8)
        if let body { response.append(body) }
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            self?.close(connection)
        })
    }

    private func close(_ connection: NWConnection) {
        connection.cancel()
    }

    /// `Range: bytes=start-end` をパースし、データ範囲（半開区間）を返す。
    private static func parseRange(_ header: String, totalLength: Int) -> Range<Int>? {
        guard let equalsIndex = header.firstIndex(of: "=") else { return nil }
        let spec = header[header.index(after: equalsIndex)...].trimmingCharacters(in: .whitespaces)
        let parts = spec.components(separatedBy: "-")
        guard let startString = parts.first, let start = Int(startString), start < totalLength else { return nil }
        let end: Int
        if parts.count > 1, let parsedEnd = Int(parts[1]), parsedEnd >= start {
            end = min(parsedEnd, totalLength - 1)
        } else {
            end = totalLength - 1
        }
        return start..<(end + 1)
    }

    /// 端末の LAN（Wi-Fi）IPv4 アドレスを返す。取得できなければ nil。
    private static func lanIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = interface.ifa_name.map { String(cString: $0) } ?? ""
                // Wi-Fi（en0）を優先して採用する。
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    // 末尾のヌル終端を取り除いて文字列化する。
                    let bytes = hostname.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                    address = String(decoding: bytes, as: UTF8.self)
                }
            }
            pointer = interface.ifa_next
        }
        return address
    }
}
