//
// Copyright (C) 2017-2019 ZeeZide GmbH, All Rights Reserved
// Created by Helge Hess on 26/01/2017.
//

import protocol ExExpress.IncomingMessage
import enum     ExExpress.console
import CApache
import func CAPR.apr_pstrdup

public class ApacheIncomingMessage : ApacheMessageBase,
                                     ExExpress.IncomingMessage,
                                     CustomStringConvertible
{

  public var httpVersion : String {
    guard let h = apacheRequest.typedHandle else { return "" }
    return h.pointee.oProtocol
  }
  
  public var method : String {
    set {
      guard let h = apacheRequest.typedHandle else { return }
      
      let mnum = ap_method_number_of(newValue)
      // TODO: check return value
      
      // Not sure this is really OK
      h.pointee.method_number = mnum
      h.pointee.method = UnsafePointer(apr_pstrdup(h.pointee.pool, newValue))
    }
    get {
      guard let h = apacheRequest.typedHandle else { return "" }
      return h.pointee.oMethod
    }
  }
  
  public var url : String {
    guard let th = apacheRequest.typedHandle else { return "" }
    return th.pointee.oUnparsedURI
  }
  
  // TODO: query

  // MARK: - Headers
  
  final override var _headersTable : OpaquePointer? {
    guard let th = apacheRequest.typedHandle else { return nil }
    return th.pointee.headers_in
  }
  
  
  // MARK: - Body
  
  public func readChunks(bufsize: Int,
                         onRead: ( UnsafeBufferPointer<UInt8> ) throws -> Void)
                throws
  {
    // TODO: Evolve this into an even better streaming source method
    guard let th = apacheRequest.typedHandle
     else {
      console.error("Could not read request body ...")
      throw Error.ApacheHandleGone
    }
    
    // Hm. Otherwise the read fails for non-empty methods. What is the proper
    // check here whether there can be a body? Content-length and TE?
    guard th.pointee.isMethodWithContent else { return }
    
    let rc = ap_setup_client_block(th, REQUEST_CHUNKED_DECHUNK)
    guard rc == 0 else {
      console.error("Could not setup request body read for \(method): \(rc)")
      throw Error.ReadFailed
    }
    
    guard ap_should_client_block(th) != 0 else {
      // There is no message to read, this is *fine*. Not an error.
      return
    }
    
    let buffer  = UnsafeMutablePointer<Int8>.allocate(capacity: bufsize)
    #if swift(>=4.2)
      defer { buffer.deallocate() }
    #else
      defer { buffer.deallocate(capacity: bufsize) }
    #endif
    
    while true {
      let rc = ap_get_client_block(th, buffer, bufsize)
      guard rc != 0 else { break } // EOF
      guard rc >  0 else { throw Error.ReadFailed }
      
      // hm
      try buffer.withMemoryRebound(to: UInt8.self, capacity: rc) { buffer in
        let bp = UnsafeBufferPointer(start: buffer, count: rc)
        try onRead(bp)
      }
    }
  }

  
  // MARK: - CustomStringConvertible
  
  public var description : String {
    var s = "<Request"
    if let h = apacheRequest.handle {
      s += "[\(h)]: "
    }
    else { s += "[gone]: " }
    s += "\(method) \(url)"
    s += ">"
    return s
  }
}

fileprivate extension request_rec {
  
  var isMethodWithContent : Bool {
    switch method_number {
      case M_GET, M_DELETE, M_OPTIONS, M_CONNECT:
        return false
      default:
        return true
    }
  }
  
}
