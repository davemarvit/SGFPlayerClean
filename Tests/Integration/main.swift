import Foundation

// Real URLSession transport against the local fixture in run_loopback.py. No OGS credentials.
let endpoint = URL(string: CommandLine.arguments[1])!
var opens = 0
var messages: [String] = []
var completed = false
var failed = false
let connection = OGSConnectionController {
    OGSURLSessionSocket(request: URLRequest(url: endpoint))
}
connection.onStateChange = { state in
    if state == .connected {
        opens += 1
        connection.send("client-command")
    }
}
connection.onMessage = { text in
    precondition(Thread.isMainThread)
    messages.append(text)
    if text == "pong-observed" {
        connection.disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            failed = opens != 2 || connection.state != .disconnected ||
                messages != ["text-1", "binary-1", "text-2", "binary-2", "pong-observed"]
            completed = true
        }
    }
}
connection.connect()
let timeout = Date().addingTimeInterval(25)
while !completed && Date() < timeout {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
connection.disconnect()
guard completed && !failed else {
    print("FAIL: opens=\(opens), messages=\(messages), completed=\(completed)")
    exit(1)
}
print("PASS: real URLSession text/binary reception, send, reconnect, ping/pong, and intentional disconnect")
