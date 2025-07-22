//
//  Headers.swift
//  EventSource
//
//  Copyright © 2023 Firdavs Khaydarov (Recouse). All rights reserved.
//  Licensed under the MIT License.
//

enum HTTPHeaderField {
    static let lastEventID = "Last-Event-ID"
    static let accept = "Accept"
    static let cacheControl = "Cache-Control"
}

enum Accept {
    static let eventStream = "text/event-stream"
}

enum CacheControl {
    static let noStore = "no-store"
}
