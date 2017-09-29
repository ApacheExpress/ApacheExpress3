//
// Copyright (C) 2017 ZeeZide GmbH, All Rights Reserved
// Created by Helge Hess on 26/01/2017.
//

import ExExpress
import CApache
import CAPR

public class ApacheServerResponse : ApacheMessageBase,
                                    ExExpress.ServerResponse,
                                    GWritableStreamType,
                                    CustomStringConvertible
{
  
  public var statusCode : Int? = nil {
    didSet {
      guard let status = statusCode           else { return }
      guard let h = apacheRequest.typedHandle else { return }
      h.pointee.status = Int32(status)
    }
  }
  
  public var headersSent = false
  
  public func writeHead(_ statusCode: Int, _ headers: Dictionary<String, Any>) {
    self.statusCode = statusCode
    
    // merge in headers
    for (key, value) in headers {
      setHeader(key, value)
    }
  }
  
  
  // MARK: - Apache builtin headers. TODO: speedz (strcasecmp?)
  // TODO: there may be more special headers? TE?

  override open var headers : Dictionary<String, Any> {
    var h = super.headers
    
    if let th = apacheRequest.typedHandle {
      if let cstr = th.pointee.content_type {
        h["Content-Type"] = String(cString: cstr)
      }
      if let cstr = th.pointee.content_encoding {
        h["Content-Encoding"] = String(cString: cstr)
      }
    }
    
    return h
  }
  
  override open func setHeader(_ name: String, _ value: Any) {
    guard let th = apacheRequest.typedHandle else { return }
    
    switch name.lowercased() {
      case "content-type":
        ap_set_content_type(th, apr_pstrdup(th.pointee.pool, "\(value)"))
      case "content-encoding":
        th.pointee.content_encoding =
          UnsafePointer(apr_pstrdup(th.pointee.pool, "\(value)"))
      case "content-language":
        fatalError("no support for content-language yet ...")
      default:
        super.setHeader(name, value)
    }
  }
  
  override open func removeHeader(_ name: String) {
    guard let th = apacheRequest.typedHandle else { return }
    
    switch name.lowercased() {
      case "content-type": // hm
        ap_set_content_type(th, apr_pstrdup(th.pointee.pool, ""))
      case "content-encoding":
        th.pointee.content_encoding =
          UnsafePointer(apr_pstrdup(th.pointee.pool, ""))
      case "content-language":
        fatalError("no support for content-language yet ...")
      default:
        super.removeHeader(name)
    }
  }
  
  override open func getHeader(_ name: String) -> Any? {
    guard let th = apacheRequest.typedHandle else { return nil }
    switch name.lowercased() {
      case "content-type":
        guard let cstr = th.pointee.content_type else { return nil }
        return String(cString: cstr)
      case "content-encoding":
        guard let cstr = th.pointee.content_encoding else { return nil }
        return String(cString: cstr)
      case "content-language":
        fatalError("no support for content-language yet ...")
      default:
        return super.getHeader(name)
    }
  }
  
  // MARK: - End Handlers
  
  var finishListeners = [ ( ServerResponse ) -> Void ]()
  
  func emitFinish() {
    while !finishListeners.isEmpty {
      let copy = finishListeners
      finishListeners.removeAll()
      
      for listener in copy {
        listener(self)
      }
    }
  }
  
  public func onceFinish(handler: @escaping ( ServerResponse ) -> Void) {
    finishListeners.append(handler)
  }
  public func onFinish(handler: @escaping ( ServerResponse ) -> Void) {
    finishListeners.append(handler)
  }
  
  // MARK: - Headers
  
  final override var _headersTable : OpaquePointer? {
    // TODO: this needs to take into account err_headers_out
    guard let h = apacheRequest.typedHandle else { return nil }
    return h.pointee.headers_out
  }
  
  
  // MARK: - Output Stream
  
  func emitBeforeHeadersSent() {
    if let app = app, app.settings.xPoweredBy,
       apr_table_get(_headersTable, "x-powered-by") == nil
    {
      let prod : String
      if let v = app.get("x-powered-by") as? String {
        switch v.lowercased() {
          case "yes", "true", "1": prod = app.productIdentifier
          default: prod = v
        }
      }
      else {
        prod = app.productIdentifier
      }
      if !prod.isEmpty { setHeader("X-Powered-By", prod) }
    }
  }
  
  open func _primaryWriteHTTPMessageHead() {
    emitBeforeHeadersSent()
    
    assert(!headersSent)
    headersSent = true
  }
  
  public func end() throws {
    guard let th = apacheRequest.typedHandle else {
      console.error("Could not end Apache request ...")
      throw(Error.ApacheHandleGone)
    }

    if !headersSent { _primaryWriteHTTPMessageHead() }
    
    let brigade = apacheRequest.createBrigade()
    let eof = apr_bucket_eos_create(brigade?.pointee.bucket_alloc)
    apz_brigade_insert_tail(brigade, eof)
    let rv = ap_pass_brigade(th.pointee.output_filters, brigade)
    
    emitFinish()
    
    if rv != APR_SUCCESS {
      throw Error.WriteFailed // TODO: Improve me ;-)
    }
  }
  
  public func writev(buckets chunks: [ [ UInt8 ] ], done: DoneCB?) throws {
    if statusCode == nil {
      writeHead(200)
    }
    
    if !headersSent { _primaryWriteHTTPMessageHead() }
    
    guard !chunks.isEmpty        else { return }
    guard !chunks.first!.isEmpty else { return }
    
    guard let h = apacheRequest.typedHandle else {
      if let cb = done { try cb() }
      console.error("Could not write to Apache request ...")
      throw(Error.ApacheHandleGone)
    }
    
    let brigade = apacheRequest.createBrigade()
    
    // Note: What we really want here is a special bucket_type that can extract
    //       the buffer from the Swift object on-demand.
    for chunk in chunks {
      try chunk.withUnsafeBufferPointer { bp in        
        // This flushes to the filter if the internal write buffer becomes
        // too large.
        let rc = apz_fwrite(h.pointee.output_filters, brigade,
                            bp.baseAddress, apr_size_t(bp.count))
        if rc < 0 {
          throw Error.WriteFailed // TODO: improve me ;-)
        }
      }
    }
    
    // This can hack the content-type. Funny, isn't it?
    let rv = ap_pass_brigade(h.pointee.output_filters, brigade)
    
    if let cb = done { try cb() }
    
    if rv != APR_SUCCESS {
      throw Error.WriteFailed // TODO: Improve me ;-)
    }
  }
  
  // MARK: - CustomStringConvertible
  
  public var description : String {
    var s = "<Response"
    if let h = apacheRequest.handle {
      s += "[\(h)]: "
    }
    else { s += "[gone]: " }
    
    if let status = self.statusCode {
      s += "\(status)"
    }
    
    s += ">"
    return s
  }
}
