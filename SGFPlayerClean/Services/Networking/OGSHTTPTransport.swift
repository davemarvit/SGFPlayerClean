import Foundation

struct OGSHTTPResponse {
    let data: Data
    let response: HTTPURLResponse

    func validatedData() throws -> Data {
        guard (200..<300).contains(response.statusCode) else {
            throw OGSHTTPError.status(response.statusCode)
        }
        return data
    }

    /// Retry-After permits either integer seconds or an HTTP date (RFC 9110 §10.2.3).
    func retryDelay(now: Date) -> TimeInterval? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces) else { return nil }
        if !header.isEmpty, header.allSatisfy({ $0.isASCII && $0.isNumber }), let seconds = Double(header), seconds.isFinite {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: header) { return max(0, date.timeIntervalSince(now)) }
        }
        return nil
    }
}

enum OGSHTTPError: LocalizedError {
    case invalidResponse, invalidJSON, invalidPagination, status(Int)
    case rejection(Int, String)
    var statusCode: Int? {
        switch self {
        case .status(let code), .rejection(let code, _): return code
        default: return nil
        }
    }
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid OGS HTTP response"
        case .invalidJSON: return "Invalid OGS response data"
        case .invalidPagination: return "Invalid or repeated OGS pagination link"
        case .status(let code): return "OGS request failed (HTTP \(code))"
        case .rejection(_, let reason): return reason
        }
    }
}

protocol OGSHTTPTransport {
    /// Completion is asynchronous on the main queue. The returned operation can be cancelled.
    func get(_ request: URLRequest, completion: @escaping (Result<OGSHTTPResponse, Error>) -> Void) -> OGSCancellable
}

extension URLSessionTask: OGSCancellable {}

struct OGSURLSessionHTTPTransport: OGSHTTPTransport {
    let session: URLSession
    func get(_ request: URLRequest, completion: @escaping (Result<OGSHTTPResponse, Error>) -> Void) -> OGSCancellable {
        precondition(request.httpMethod == nil || request.httpMethod == "GET")
        let task = session.dataTask(with: request) { data, response, error in
            let result: Result<OGSHTTPResponse, Error>
            if let error { result = .failure(error) }
            else if let data, let response = response as? HTTPURLResponse {
                result = .success(OGSHTTPResponse(data: data, response: response))
            } else { result = .failure(OGSHTTPError.invalidResponse) }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        return task
    }
}
