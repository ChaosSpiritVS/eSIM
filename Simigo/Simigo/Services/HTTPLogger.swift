import Foundation

/// 统一的 HTTP 调试日志（仅在 Debug 构建下输出）
struct HTTPLogger {
    static func logRequest<Body: Encodable>(method: String, path: String, body: Body) {
        #if DEBUG
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.dateEncodingStrategy = .iso8601
        let bodyString: String
        if let data = try? encoder.encode(body), let str = String(data: data, encoding: .utf8) {
            bodyString = str
        } else {
            bodyString = String(describing: body)
        }
        print("[HTTP-REQ] method=\(method) path=\(path) body=\(bodyString)")
        #endif
    }

    static func logResponse<Response: Encodable>(method: String, path: String, response: Response) {
        #if DEBUG
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.dateEncodingStrategy = .iso8601
        let respString: String
        if let data = try? encoder.encode(response), let str = String(data: data, encoding: .utf8) {
            respString = str
        } else {
            respString = String(describing: response)
        }
        print("[HTTP-RESP] method=\(method) path=\(path) body=\(respString)")
        #endif
    }

    // 兼容仅 Decodable 或非 Encodable 的类型，避免编译错误
    static func logResponse(method: String, path: String, response: Any) {
        #if DEBUG
        let respString = String(describing: response)
        print("[HTTP-RESP] method=\(method) path=\(path) body=\(respString)")
        #endif
    }

    static func logError(method: String, path: String, error: Error) {
        #if DEBUG
        print("[HTTP-ERR] method=\(method) path=\(path) error=\(error.localizedDescription)")
        #endif
    }
}