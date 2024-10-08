#import std/[posix, streams, strutils]
import ba0f3/[logger]
from chronos import waitFor
import spoa/[agent]

when isMainModule:
  initLogger()
  waitFor SpoeAgent.new("0.0.0.0:12345").run()