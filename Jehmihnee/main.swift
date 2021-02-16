//
//  main.swift
//  Jehmihnee
//
//  Created by Fredrik Broman on 2021-02-05.
//
//  Inspired by a post by Eskimo in this thread: https://developer.apple.com/forums/thread/116723
//

import ArgumentParser
import Foundation
import Network

@available(macOS 10.14, *)
class Main {

    init(hostName: String, port: Int) {
        let host = NWEndpoint.Host(hostName)
        let port = NWEndpoint.Port("\(port)")!
        let parameters = Main.getTLSParameters(allowInsecure: true, queue: .main)
        self.connection = NWConnection(host: host, port: port, using: parameters)
    }

    let connection: NWConnection

    func start() {
        NSLog("will start")
        self.connection.stateUpdateHandler = self.didChange(state:)
        self.startReceive()
        self.connection.start(queue: .main)
    }

    func stop() {
        self.connection.cancel()
        NSLog("did stop")
        exit(EXIT_SUCCESS)
    }

    private func didChange(state: NWConnection.State) {
        switch state {
        case .setup:
            break
        case .waiting(let error):
            NSLog("is waiting: %@", "\(error)")
        case .preparing:
            break
        case .ready:
            break
        case .failed(let error):
            NSLog("did fail, error: %@", "\(error)")
            self.stop()
        case .cancelled:
            NSLog("was cancelled")
            self.stop()
        @unknown default:
            break
        }
    }

    private func startReceive() {
        self.connection.receiveMessage { (data, _, isDone, error) in
            if let data = data, !data.isEmpty {
                let datastring = NSString(data: data, encoding: String.Encoding.utf8.rawValue)!
                print(datastring as Any)
            }
            if let error = error {
                NSLog("did receive, error: %@", "\(error)")
                self.stop()
                return
            }
            if isDone {
                NSLog("did receive, EOF")
                self.stop()
                return
            }
            self.startReceive()
        }
    }

    func send(line: String) {
        let data = Data("\(line)\r\n".utf8)
        self.connection.send(content: data, completion: NWConnection.SendCompletion.contentProcessed { error in
            if let error = error {
                NSLog("did send, error: %@", "\(error)")
                self.stop()
            } else {
                NSLog("did send, data: %@", data as NSData)
            }
        })
    }

    // Ignore self signed certs https://developer.apple.com/forums/thread/104018
    // TODO: https://drewdevault.com/2020/09/21/Gemini-TOFU.html
    static private func getTLSParameters(allowInsecure: Bool, queue: DispatchQueue) -> NWParameters {
        let options = NWProtocolTLS.Options()

        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { (sec_protocol_metadata, sec_trust, sec_protocol_verify_complete) in
            
            let trust = sec_trust_copy_ref(sec_trust).takeRetainedValue()
            
            var error: CFError?
            if SecTrustEvaluateWithError(trust, &error) {
                sec_protocol_verify_complete(true)
            } else {
                if allowInsecure == true {
                    sec_protocol_verify_complete(true)
                } else {
                    sec_protocol_verify_complete(false)
                }
            }
            
        }, queue)
        
        return NWParameters(tls: options)
    }

    static func run(opts: Opts) -> Never {
        guard let url = URL(string: opts.url) else {
            print("Could not parse argument as URL")
            exit(EXIT_FAILURE)
        }

        guard url.scheme == "gemini" else {
            print("Only gemini:// protocol supported")
            exit(EXIT_FAILURE)
        }

        let m = Main(hostName: url.host!, port: opts.port ?? 1965)
        m.start()

        m.send(line: url.absoluteString)
        dispatchMain()
    }
}

struct Opts: ParsableArguments {
    @Argument(help: "gemini url") var url: String
    @Argument(help: "gemini port, default 1965") var port: Int?
    @Flag(help: "Show verbose output") var verbose = false
}

let options = Opts.parseOrExit()

guard options.url.count < 1024 else {
    print("URL must be shorter than 1024 chars")
    exit(EXIT_FAILURE)
}

Main.run(opts: options)
