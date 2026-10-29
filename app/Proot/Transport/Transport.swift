import Foundation

enum LinkState: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
}

/// A byte pipe to the visor. Messages are whole JSON documents or binary payloads.
protocol Transport: AnyObject {
    var onMessage: ((Data, Bool) -> Void)? { get set }  // payload, isBinary
    var onState: ((LinkState) -> Void)? { get set }
    var maxBinaryChunk: Int { get }
    var isBLE: Bool { get }
    func send(_ data: Data, binary: Bool)
    func close()
}

final class WebSocketTransport: NSObject, Transport, URLSessionWebSocketDelegate {
    var onMessage: ((Data, Bool) -> Void)?
    var onState: ((LinkState) -> Void)?
    let maxBinaryChunk = 4096
    let isBLE = false
    let host: String
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?

    init(host: String) {
        self.host = host
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    func open() {
        guard let url = URL(string: "ws://\(host)/ws") else {
            onState?(.failed("Bad address"))
            return
        }
        onState?(.connecting)
        task = session.webSocketTask(with: url)
        task?.resume()
        receive()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let s)):
                self.onMessage?(Data(s.utf8), false)
                self.receive()
            case .success(.data(let d)):
                self.onMessage?(d, true)
                self.receive()
            case .success:
                self.receive()
            case .failure(let e):
                self.onState?(.failed(e.localizedDescription))
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        onState?(.connected)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        onState?(.failed("Connection closed"))
    }

    func send(_ data: Data, binary: Bool) {
        let msg: URLSessionWebSocketTask.Message = binary ? .data(data) : .string(String(decoding: data, as: UTF8.self))
        task?.send(msg) { _ in }
    }

    func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }
}
