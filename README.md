<h2>ApacheExpress3
  <img src="http://zeezide.com/img/ApexIcon1024.svg"
       align="right" width="128" height="128" />
</h2>

![Apache 2](https://img.shields.io/badge/apache-2-yellow.svg)
![Swift3](https://img.shields.io/badge/swift-3-blue.svg)
![macOS](https://img.shields.io/badge/os-macOS-green.svg?style=flat)
![Travis](https://travis-ci.org/ApacheExpress3/ApacheExpress3.svg?branch=master)

ApacheExpress allows you to quickly write Server Side 
[Swift](http://swift.org/) 
applications which run as a native module within the
[Apache Web Server](https://httpd.apache.org).

TODO: Cleanup the README.
[mods_expressdemo](../mods_expressdemo/README.md)

A very basic request/response handler:

```Swift
public func ApacheMain(_ cmd: OpaquePointer) {
  let app = ApacheExpress.express(cmd)
  app.server.onRequest { req, res in
    res.writeHead(200, [ "Content-Type": "text/html" ])
    try res.end("<h1>Hello World</h1>")
  }
}
```

Connect like reusable middleware:

```Swift
public func ApacheMain(_ cmd: OpaquePointer) {
  let app = ApacheExpress.express(cmd)
  
  app.use { req, res, next in
    console.info("Request is passing Connect middleware ...")
    res.setHeader("Content-Type", "text/html; charset=utf-8")
    next()
  }
  
  app.use("/connect") { req, res, next in
    try res.write("<p>This is a random cow:</p><pre>")
    try res.write(vaca())
    try res.write("</pre>")
    res.end()
  }
}
```

And the Apache Express is about to leave:
```Swift
public func ApacheMain(_ cmd: OpaquePointer) {
  let app = apache.express(cookieParser(), session())

  app.get("/express/cookies") { req, res, _ in
    // returns all cookies as JSON
    try res.json(req.cookies)
  }

  app.get("/express/") { req, res, _ in
    let tagline = arc4random_uniform(UInt32(taglines.count))
    
    let values : [ String : Any ] = [
      "tagline"     : taglines[Int(tagline)],
      "viewCount"   : req.session["viewCount"] ?? 0,
      "cowOfTheDay" : cows.vaca()
    ]
    try res.render("index", values)
  }
}
```

Yes. All that is running within Apache.
