//
//  ApacheReloadMiddleware.swift
//  ApacheExpress3
//
//  Created by Helge Hess on 09/05/17.
//  Copyright © 2017 ZeeZide GmbH. All rights reserved.
//


/**
 * A simple middleware which simply sends the `SIGHUP` signal to the Apache
 * master process.
 * This tells Apache to perform a graceful restart. That is the configuration
 * and modules are reloaded, but the child processes are allowed to finish up
 * the connections they are currently processing.
 *
 * By default this middleware is restricted to the `development` environment
 * for hopefully obvious reasons :->
 *
 * Note: This does NOT work for an Apache instance run from within Xcode.
 *       This is because our Xcode configs start Apache in debug mode (`-X`),
 *       which means it doesn't fork.
 *
 * IMPORTANT: Be careful w/ using that extension. It is best to turn in off
 *            completely in deployments.
 */
public func apacheReload(enabledIn: [ String ] = [ "development" ])
            -> Middleware
{
  return { req, res, _ in
    guard let env = req.app?.settings.env, enabledIn.contains(env) else {
      // TBD: well, how do I just cancel this specific route and bubble up? We
      //      could throw a specific error? (Route.Skip?)
      console.warn("attempt to access apache-reload in disabled env:",
                   req.app?.settings.env, req)
      return try res.sendStatus(404) // FIXME
    }
    
    guard !process.isRunningInXCode else {
      res.statusCode = 403
      return try res.json([
        "error":   403,
        "message": "Cannot reload Apache when it is running in Xcode!"
      ])
    }
    
    let pid  = getpid()
    let ppid = getppid()
    
    console.log("\(pid): sending SIGHUP to parent process \(ppid) ...")
    kill(ppid, SIGHUP)
    console.log("done.")
    
    return try res.json([
      "processID":       pid,
      "parentProcessID": ppid
    ])
  }
}

#if os(Linux)
  import Glibc
#else
  import Darwin
#endif
