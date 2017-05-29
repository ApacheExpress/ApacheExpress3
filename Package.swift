import PackageDescription

let package = Package(
  name: "ApacheExpress3",

  targets: [ Target(name: "ApacheExpress3") ],
  
  dependencies: [
    .Package(url: "https://github.com/modswift/CApache.git", 
             majorVersion: 1, minor: 0),
    .Package(url: "https://github.com/modswift/ExExpress.git",
             majorVersion: 0)
  ],
	
  exclude: [
    "ApacheExpress.xcodeproj",
    "GNUmakefile",
    "LICENSE",
    "README.md",
    "xcconfig"
  ]
)
