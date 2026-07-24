import Foundation

/// Line-delimited JSON-RPC 2.0 over a Unix domain stream socket.
final class RpcServer {
    private let path: String
    private var serverFd: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "mx.rpc", qos: .userInitiated)
    private var clients: [Int32: DispatchSourceRead] = [:]
    var handler: ((String, [String: Any]?) -> [String: Any])?

    init(path: String) {
        self.path = path
    }

    func start() throws {
        // Remove stale sockets (including previous TMPDIR-based paths if present).
        unlink(path)
        unlink((NSTemporaryDirectory() as NSString).appendingPathComponent("logioptions.sock"))
        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else { throw RpcError.socket }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw RpcError.pathTooLong
        }
        _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            pathBytes.withUnsafeBufferPointer { buf in
                memcpy(ptr, buf.baseAddress!, min(buf.count, 104))
            }
        }

        let bindRc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindRc == 0 else { throw RpcError.bind }
        guard listen(serverFd, 4) == 0 else { throw RpcError.listen }

        // World-readable socket in /tmp is fine for local single-user tool
        chmod(path, 0o666)

        let src = DispatchSource.makeReadSource(fileDescriptor: serverFd, queue: queue)
        src.setEventHandler { [weak self] in
            self?.acceptClient()
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.serverFd, fd >= 0 { close(fd) }
        }
        src.resume()
        source = src
        DaemonLog.info("RPC listening on \(path)")
    }

    func stop() {
        source?.cancel()
        source = nil
        for (_, src) in clients {
            src.cancel()
        }
        clients.removeAll()
        if serverFd >= 0 {
            close(serverFd)
            serverFd = -1
        }
        unlink(path)
    }

    private func acceptClient() {
        let client = accept(serverFd, nil, nil)
        guard client >= 0 else { return }
        let src = DispatchSource.makeReadSource(fileDescriptor: client, queue: queue)
        var buffer = Data()
        src.setEventHandler { [weak self] in
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = read(client, &chunk, chunk.count)
            if n <= 0 {
                src.cancel()
                self?.queue.async {
                    self?.clients.removeValue(forKey: client)
                }
                close(client)
                return
            }
            buffer.append(contentsOf: chunk.prefix(n))
            while let range = buffer.range(of: Data([0x0A])) {
                let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                if let response = self?.handleLine(line) {
                    var out = response
                    out.append(0x0A)
                    _ = out.withUnsafeBytes { raw in
                        write(client, raw.baseAddress!, out.count)
                    }
                }
            }
        }
        src.setCancelHandler {
            close(client)
        }
        src.resume()
        clients[client] = src
    }

    private func handleLine(_ data: Data) -> Data? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = obj["method"] as? String else {
            return encode([
                "jsonrpc": "2.0",
                "error": ["code": -32700, "message": "parse error"],
                "id": NSNull(),
            ])
        }
        let id = obj["id"]
        let params = obj["params"] as? [String: Any]
        let result = handler?(method, params) ?? ["ok": false, "error": "no handler"]
        if result["__notification"] as? Bool == true {
            return nil
        }
        if let err = result["error"] as? String, result["ok"] as? Bool == false {
            return encode([
                "jsonrpc": "2.0",
                "error": ["code": -32000, "message": err],
                "id": id as Any,
            ])
        }
        return encode([
            "jsonrpc": "2.0",
            "result": result,
            "id": id as Any,
        ])
    }

    private func encode(_ obj: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: obj)
    }
}

enum RpcError: Error {
    case socket, bind, listen, pathTooLong
}
