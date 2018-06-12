/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import CoreBluetooth

public class McuManager {
    
    //**************************************************************************
    // MARK: Mcu Manager Constants
    //**************************************************************************
    
    /// Mcu Manager CoAP Resource URI
    public static let COAP_PATH = "/omgr"
    
    /// Header Key for CoAP Payloads
    public static let HEADER_KEY = "_h"
    
    //**************************************************************************
    // MARK: Properties
    //**************************************************************************

    /// Handles transporting Mcu Manager commands
    public var transporter: McuMgrTransport!
    
    /// The command group used for in the header of commands sent using this Mcu
    /// Manager
    public var group: McuMgrGroup!
    
    //**************************************************************************
    // MARK: Initializers
    //**************************************************************************

    public init(group: McuMgrGroup, transporter: McuMgrTransport) {
        self.group = group
        self.transporter = transporter
    }
    
    //**************************************************************************
    // MARK: Send Commands
    //**************************************************************************

    public func send<T: McuMgrResponse>(op: McuMgrOperation, commandId: UInt8, payload: [String:CBOR]?, callback: @escaping McuMgrCallback<T>) {
        send(op: op, flags: 0, group: group, sequenceNumber: 0, commandId: commandId, payload: payload, callback: callback)
    }
    
    public func send<T: McuMgrResponse>(op: McuMgrOperation, flags: UInt8, group: McuMgrGroup, sequenceNumber: UInt8, commandId: UInt8, payload: [String:CBOR]?, callback: @escaping McuMgrCallback<T>) {
        let data = buildPacket(op: op, flags: flags, group: group, sequenceNumber: sequenceNumber, commandId: commandId, payload: payload)
        send(data: data, callback: callback)
    }
    
    public func send<T: McuMgrResponse>(data: Data, callback: @escaping McuMgrCallback<T>) {
        transporter.send(data: data, callback: callback)
    }
    
    //**************************************************************************
    // MARK: Build Request Packet
    //**************************************************************************
    
    /// Build a McuManager request packet based on the transporter scheme.
    ///
    /// - parameter op: The McuManagerOperation code
    /// - parameter flags: The optional flags
    /// - parameter group: The command group
    /// - parameter sequenceNumber: The optional sequence number
    /// - parameter commandId: The command id
    /// - parameter payload: The request payload
    ///
    /// - returns: The raw packet data to send to the transporter
    public func buildPacket(op: McuMgrOperation, flags: UInt8, group: McuMgrGroup, sequenceNumber: UInt8, commandId: UInt8, payload: [String:CBOR]?) -> Data {
        // If the payload map is nil, initialize an empty map
        var payload = (payload == nil ? [:] : payload)!
        
        // Copy the payload map to remove the header key
        var payloadCopy = payload
        // Remove the header if present (for CoAP schemes)
        payloadCopy.removeValue(forKey: McuManager.HEADER_KEY)
        
        // Get the length
        let len: UInt16 = UInt16(CBOR.encode(payloadCopy).count)
        
        // Build header
        let header = McuMgrHeader.build(op: op.rawValue, flags: flags, len: len, group: group.rawValue, seq: sequenceNumber, id: commandId)
        
        // Build the packet based on scheme
        if transporter.getScheme().isCoap() {
            // CoAP transport schemes puts the header as a key-value pair in the
            // payload
            if payload[McuManager.HEADER_KEY] == nil {
                payload.updateValue(CBOR.byteString(header), forKey: McuManager.HEADER_KEY)
            }
            return Data(CBOR.encode(payload))
        } else {
            // Standard scheme appends the CBOR payload to the header
            let cborPayload = CBOR.encode(payload)
            var packet = Data(bytes: header)
            packet.append(contentsOf: cborPayload)
            return packet
        }
    }
    
    //**************************************************************************
    // MARK: Utilities
    //**************************************************************************

    /// Converts a date and optional timezone to a string which Mcu Manager on
    /// the device can use.
    ///
    /// The date format used is: "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
    ///
    /// - parameter date: The date
    /// - parameter timeZone: Optional timezone for the given date. If left out
    ///   or nil, the timzone will be set to the system time zone.
    ///
    /// - returns: The datetime string
    public static func dateToString(date: Date, timeZone: TimeZone? = nil) -> String {
        let RFC3339DateFormatter = DateFormatter()
        RFC3339DateFormatter.locale = Locale(identifier: "en_US_POSIX")
        RFC3339DateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        RFC3339DateFormatter.timeZone = (timeZone != nil ? timeZone : TimeZone.current)
        return RFC3339DateFormatter.string(from: date)
    }
}

/// McuManager callback
public typealias McuMgrCallback<T: McuMgrResponse> = (T?, Error?) -> Void

/// The defined groups for Mcu Manager commands.
///
/// Each group has its own manager class which contains the specific subcommands
/// and functions. The default are contained within the McuManager class.
public enum McuMgrGroup: UInt16 {
    /// Default command group (DefaultManager).
    case `default`  = 0
    /// Image command group (ImageManager).
    case image      = 1
    /// Statistics command group (StatsManager).
    case stats      = 2
    /// System configuration command group (ConfigManager).
    case config     = 3
    /// Log command group (LogManager).
    case logs       = 4
    /// Crash command group (CrashManager).
    case crash      = 5
    /// Split image command group (Not implemented).
    case split      = 6
    /// Run test command group (RunManager).
    case run        = 7
    /// File System command group (FileSystemManager).
    case fs         = 8
    /// Per user command group.
    case peruser    = 64
}

/// The mcu manager operation defines whether the packet sent is a read/write
/// and request/response.
public enum McuMgrOperation: UInt8 {
    case read           = 0
    case readResponse   = 1
    case write          = 2
    case writeResponse  = 3
}

/// Return codes for Mcu Manager responses.
///
/// Each Mcu Manager response will contain a "rc" key with one of these return
/// codes.
public enum McuMgrReturnCode: UInt, Error {
    case ok         = 0
    case unknown    = 1
    case noMemory   = 2
    case inValue    = 3
    case timeout    = 4
    case noEntry    = 5
    case badState   = 6
    case unrecognized
    public var localizedDescription: String {
        switch self {
        case .ok:
            return "OK (0)"
        case .unknown:
            return "Unknown (1)"
        case .noMemory:
            return "No Memory (2)"
        case .inValue:
            return "In Value (3)"
        case .timeout:
            return "Timeout (4)"
        case .noEntry:
            return "No Entry (5)"
        case .badState:
            return "Bad State (1)"
        default:
            return "Unrecognized (\(rawValue))"
        }
    }
    public func isSuccess() -> Bool {
        return self == .ok
    }
    public func isError() -> Bool {
        return self != .ok
    }
}

/// McuManager transport scheme
public enum McuMgrScheme {
    case ble, coapBle, coapUdp
    func isCoap() -> Bool {
        return self != .ble
    }
}