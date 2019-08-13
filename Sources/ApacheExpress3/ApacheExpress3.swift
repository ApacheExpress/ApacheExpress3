//
//  ApacheExpress.swift
//  mod_swift
//
//  Created by Helge Heß on 4/3/16.
//  Copyright © 2016 ZeeZide GmbH. All rights reserved.
//

import class ExExpress.Express
import enum  ExExpress.process
import CApache

fileprivate var apps = [ ApacheExpress ]() // only fill during setup phase!

public typealias ApacheExpressPostConfigCB = ( ApacheExpress ) -> ()
public typealias ApacheExpressChildInitCB  = ( ApacheExpress ) -> ()

fileprivate let debug        = false
fileprivate let requiresName = false

/**
 * The main Application object for an ApacheExpress application.
 *
 * This is the top-level Express application object which hooks ExExpress up
 * with Apache. It is usually setup in the `ApacheMain` function of the
 * mod_swift module.
 *
 * Example:
 *
 *     @_cdecl("ApacheMain")
 *     public func ApacheMain(cmd: OpaquePointer) {
 *     let app = ApacheExpress.express(cmd)
 *     app.use("/hello") { req, res, next in
 *       try res.send("<h1>Hello Connect!</h1>")
 *     }
 *
 * This subclass of `Express` adds just the stuff required for driving Apache,
 * most of the functionality comes from its superclass `Express`.
 *
 * The express function requires that you pass in the `cmd` parameter you
 * receive from ApacheMain. But it also features a set of other parameters:
 *
 * ## Parameters
 *
 * ### name
 *
 * The name of the Apache module as it registered with Apache, for example 
 * `mods_hello`. This should be set to a sensible value, it is used in logging
 * and other parts of Apache.
 *
 * If you are running with a static build of ApacheExpress, Apex will try to
 * derive the name from the loaded module. If you link to libApacheExpress
 * dynamically, it can't do this and you have to specify the name.
 *
 * ### handler
 *
 * Apache normally selects the module which should serve a request based on the
 * `handler`. A handler can be configured in the apache.conf by various means,
 * for example:
 *
 *     AddHandler mustache-handler .mustache
 *
 * This will set the handler for files ending in `.mustache` to
 * "mustache-handler".
 *
 * Using the `handler` parameter you can assign a handler to your Express
 * application. That is - the application will only run if the handler is
 * properly configured in the apache.conf.
 *
 * By default this check is off, but it is highly recommended to assign and
 * configure a proper handler name for deployment configurations.
 *
 * Example:
 *
 *     let app = ApacheExpress.express(cmd, handler: "awesome-handler")
 *     app.use("/hello") { req, res, next in ... }
 *
 * The app will only be active if the "awesome-handler" is configured in Apache,
 * e.g. like this:
 *
 *     <Location /awesome>
 *       SetHandler awesome-handler
 *     </Location>
 *
 * Note: handler names are case-insensitive.
 *
 * ### mount
 *
 * The ApacheExpress content handler runs very early and can usually capture any
 * request passed into Apache.
 * If you just want to host your application under a sub-url, you can assign a
 * prefix path. This mounts your app to Apache just like another app can mount
 * to your app.
 * Example:
 *
 *     let app = ApacheExpress.express(cmd, mount: "/awesome")
 *     app.use("/hello") { req, res, next in ... }
 *
 * This would make the `/hello` route run if the browser invokes 
 * `/awesome/hello`.
 *
 * ### Array of middleware
 *
 * You can already assign middleware during application, setup. Like so:
 *
 *     let app = ApacheExpress.express(cmd, cookieParser(), session())
 *
 * ### Post Config Handler
 *
 * The final argument to `express` is the post-config callback. This is called
 * after Apache is fully configured and ready to start (kinda like
 * `applicationdDidFinishLaunching` in iOS.
 * It is recommended to put all your setup work into this handler.
 *
 * Note: Everything you call in `ApacheMain` is executed while the
 *       mod_swift `LoadSwiftModule` directive is processed. Use the post config
 *       handler to decouple the actual module setup from the application
 *       configuration.
 *
 * Example:
 *
 *     @_cdecl("ApacheMain")
 *     public func ApacheMain(cmd: OpaquePointer) {
 *       let app = ApacheExpress.express(cmd) { app in
 *         app.use("/hello") { req, res, next in
 *           try res.send("<h1>Hello Connect!</h1>")
 *         }
 *       }
 *     }
 *
 * This has one extra nesting, but is the more correct thing to do :-)
 */
open class ApacheExpress : Express {
  
  // MARK: - Embed Server
  
  public let server : http_internal.ApacheServer
  public var module : CApache.module
  
  let postConfig : ApacheExpressPostConfigCB?
  let childInit  : ApacheExpressChildInitCB? = nil
  let handler    : String?
  
  public init(loadCommand cmd: UnsafeMutablePointer<cmd_parms>,
              name       : String,
              handler    : String?,
              postConfig : ApacheExpressPostConfigCB?,
              mount      : String?)
  {
    server = http_internal.ApacheServer(handle: cmd.pointee.server)
    module = CApache.module(name: name, register_hooks: register_hooks)
    self.handler    = handler?.lowercased() // always lower in Apache
    self.postConfig = postConfig
    
    super.init(id: name == defaultName ? nil : name, mount: mount)
    
    server.onRequest { [unowned self] in try self.requestHandler($0, $1) }
    
    if debug { console.log("\(#function) init ApEx") }
  }
  deinit {
    if debug { console.log("\(#function) deinit ApEx") }
  }
  
  
  /**
   * Use this function the setup the main ApacheExpress application and bind it
   * to Apache. Checkout the ApacheExpress class documentation for the meaning
   * of the parameters.
   */
  @discardableResult
  public static func express(_ cmd      : OpaquePointer,
                             name       : String? = nil,
                             handler    : String? = nil,
                             mount      : String? = nil,
                             middleware : Middleware...,
                             postConfig : ApacheExpressPostConfigCB? = nil )
                     -> ApacheExpress
  {
    let typedCmd = UnsafeMutablePointer<cmd_parms>(cmd)
    let modname = name ?? getApacheModuleName()
    
    let app = ApacheExpress(loadCommand: typedCmd, name: modname,
                            handler: handler, postConfig: postConfig,
                            mount: mount)
    
    for m in middleware {
      _ = app.use(m)
    }
    
    // FIXME: I think we need to use the config pool to release the object!
    //        Currently we leak all this thing once during the Apache 2-phase
    //        setup.
    apps.append(app)
    
    if debug { console.log("\(#function) register module ..") }
    let rc = apz_register_swift_module(typedCmd, &app.module)
    assert(rc == APR_SUCCESS, "Could not add Swift module!")
    if debug { console.log("\(#function) done registering module.") }
    return app
  }
  
  
  // MARK: - Extension Point for Subclasses
  
  override
  open func viewDirectory(for engine: String, response: ServerResponse)
            -> String
  {
    guard let ar = response as? ApacheServerResponse else {
      return super.viewDirectory(for: engine, response: response)
    }
    
    // Maybe that should be an array
    // This should allow 'views' as a relative path.
    // Also, in Apache it should be a configuration directive.
    let viewsPath = (get("views") as? String)
                 ?? process.env["EXPRESS_VIEWS"]
                 ?? ar.apacheRequest.pathRelativeToServerRoot(filename: "views")
                 ?? process.cwd()
    return viewsPath
  }
  
  // MARK: - Override top-level RequestHandler

  public var requestHandler: RequestEventCB {
    return { [unowned self] req, res in
      let errorToThrow : Error?
      
      // global module preconditions
      
      if let handler = self.handler, !handler.isEmpty,
         let ar = (req as? ApacheIncomingMessage)?.apacheRequest,
         let activeHandler = ar.typedHandle?.pointee.handler
      {
        guard strcmp(activeHandler, handler) == 0 else { return }
      }
      
      // trigger middleware stack
      
      do {
        #if swift(>=4.2)
        try self.handle(error: nil, request: req, response: res, next: { 
          (args : Any...) in
          // essentially the final handler
          // Unlike ExExpress we don't do anything in here, we let Apache
          // continue its handler processing.
        })
        #else
        try self.handle(error: nil, request: req, response: res, next: { _ in
          // essentially the final handler
          // Unlike ExExpress we don't do anything in here, we let Apache
          // continue its handler processing.
        })
        #endif
        errorToThrow = nil
      }
      catch (let _error) {
        errorToThrow = _error
      }
      
      // finally
      // break potential retain cycles
      self.clearAttachedState(request: req, response: res)
      
      if let error = errorToThrow {
        throw error
      }
    }
  }

  
  /// The identifier used in the x-powered-by header
  override open var productIdentifier : String {
    return "http://ApacheExpress.io/"
  }
}


// MARK: - Apache Handler

fileprivate func registerCleanup(p: UnsafeMutableRawPointer?) -> apr_status_t {
  guard didRegisterHooks else { return OK }
  didRegisterHooks = false

  apps.removeAll()
  return OK
}
fileprivate func childCleanup(p: UnsafeMutableRawPointer?) -> apr_status_t {
  return OK
}


// The main entry point to generate ApacheExpress.http server callbacks
fileprivate func ApacheExpressHandler(p: UnsafeMutablePointer<request_rec>?)
                 -> Int32
{
  for app in apps {
    let rc = app.server.handler(request: p)
    if rc != DECLINED { return rc }
  }
  return DECLINED
}

fileprivate
func ApacheExpressPostConfig(pconf:  OpaquePointer?,
                             plog:   OpaquePointer?,
                             ptemp:  OpaquePointer?,
                             server: UnsafeMutablePointer<server_rec>?) -> Int32
{
  for app in apps {
    if let cb = app.postConfig {
      if debug {
        console.log("\(#function) running postConfig for: \(app)")
      }
      cb(app)
    }
    else if debug {
      console.log("\(#function) not running postConfig for: \(app)")
    }
  }
  return OK
}

fileprivate
func ApacheExpressChildInit(pool: OpaquePointer?,
                            server: UnsafeMutablePointer<server_rec>?)
{
  for app in apps {
    if let cb = app.childInit {
      if debug {
        console.log("\(#function) running childInit for: \(app)")
      }
      cb(app)
    }
    else if debug {
      console.log("\(#function) not running childInit for: \(app)")
    }
  }
}


fileprivate var didRegisterHooks = false
fileprivate func register_hooks(pool: OpaquePointer?) {
  // Note: in ApacheExpress all modules may share the same hook!
  
  guard !didRegisterHooks else {
    if debug { console.log("\(#function): hooks already setup") }
    return
  }
  didRegisterHooks = true
  
  if debug { console.log("\(#function): setup hooks for module") }
  ap_hook_handler    (ApacheExpressHandler,    nil, nil, APR_HOOK_FIRST)
  ap_hook_post_config(ApacheExpressPostConfig, nil, nil, APR_HOOK_LAST)
  ap_hook_child_init (ApacheExpressChildInit,  nil, nil, APR_HOOK_MIDDLE)
  
  apr_pool_cleanup_register(pool, nil, registerCleanup, childCleanup)
}

#if os(Linux)
  import Glibc
#endif

fileprivate let defaultName = "UnnamedApacheExpressModule"
fileprivate var modref = 1337
fileprivate func getCurrentModuleName() -> String? {
  #if os(Linux)
    // Swift 3.0.2/3.1 Linux barks on Dl_info/dladdr
    return nil
  #else
    // This only works for static linkage!
    var info = Dl_info()
    guard dladdr(&modref, &info) != 0 else { return nil }
    guard let cstr = info.dli_fname   else { return nil }
    let name = String(cString: cstr)
    return name.isEmpty ? nil : name
  #endif
}
fileprivate func getApacheModuleName() -> String {
  var name = getCurrentModuleName()
  if let n = name {
    if n.contains("libswiftCore.") {
      if requiresName { console.info("detected swiftCore as module? :-)") }
      name = nil
    }
    else if n.contains("libApacheExpress.") {
      if requiresName {
        console.info("ApacheExpress is linked dynamically, " +
                     "cannot auto-detect name.")
      }
      name = nil
    }
  }
  
  guard let modname = name else {
    if requiresName { console.error("Could not determine Swift module name.") }
    return defaultName
  }
  
  return modname
}
