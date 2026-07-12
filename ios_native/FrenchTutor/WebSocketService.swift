import Foundation

class WebSocketService: NSObject {
    private var task: URLSessionWebSocketTask?
    private let session: URLSession
    private let serverUrl: String

    var onStatus: ((SessionStatus) -> Void)?
    var onTranscript: ((String, String) -> Void)?
    var onSpeak: ((String) -> Void)?
    var onSummary: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onDisconnect: (() -> Void)?
    var onGoal: ((String) -> Void)?

    init(serverUrl: String) {
        self.serverUrl = serverUrl
        self.session = URLSession(configuration: .default)
        super.init()
    }

    func connect(sessionId: String) {
        let url = URL(string: "\(serverUrl)/ws/\(sessionId)")!
        task = session.webSocketTask(with: url)
        task?.resume()
        receiveMessages()
    }

    private func receiveMessages() {
        task?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                default:
                    break
                }
                self?.receiveMessages()
            case .failure:
                DispatchQueue.main.async {
                    self?.onDisconnect?()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = msg["type"] as? String else { return }

        DispatchQueue.main.async {
            switch type {
            case "status":
                let statusStr = msg["status"] as? String ?? ""
                let status = SessionStatus(rawValue: statusStr) ?? .idle
                self.onStatus?(status)

            case "transcript":
                let role = msg["role"] as? String ?? ""
                let text = msg["text"] as? String ?? ""
                self.onTranscript?(role, text)

            case "speak":
                let text = msg["text"] as? String ?? ""
                self.onSpeak?(text)

            case "goal":
                let goal = msg["goal"] as? String ?? ""
                self.onGoal?(goal)

            case "session_ended":
                let summary = msg["summary"] as? String ?? ""
                self.onSummary?(summary)
                self.onStatus?(.ended)

            case "error":
                let message = msg["message"] as? String ?? "Unknown error"
                self.onError?(message)

            default:
                break
            }
        }
    }

    func sendStart() {
        send(["type": "start"])
    }

    func sendAudio(_ data: Data) {
        let b64 = data.base64EncodedString()
        send(["type": "audio", "data": b64])
    }

    func sendEnd() {
        send(["type": "end"])
    }

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { _ in }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }
}
