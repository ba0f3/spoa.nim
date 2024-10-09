# Package

version       = "0.1.1"
author        = "Huy Doan"
description   = "HAProxy Stream Processing Offload Agent"
license       = "MIT"
srcDir        = "src"
skipDirs      = @[".vscode", "tests", "examples", "fuzz"]

# Dependencies

requires "nim >= 2.2.0", "chronos >= 4.0.3", "chronicles >= 0.4.2"
