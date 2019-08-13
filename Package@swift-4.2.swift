// swift-tools-version:4.2
import PackageDescription

let package = Package(
  name: "ApacheExpress3",

  products: [
    .library(name: "ApacheExpress3", targets: [ "ApacheExpress3" ]),
  ],
  
  dependencies: [
    .package(url: "https://github.com/modswift/CApache.git", 
             from: "2.0.1"),
    .package(url: "https://github.com/modswift/ExExpress.git",
             from: "0.7.0")
  ],
	
  targets: [ 
    .target(name: "ApacheExpress3", dependencies: [ "CApache", "ExExpress" ]) 
  ]
)
