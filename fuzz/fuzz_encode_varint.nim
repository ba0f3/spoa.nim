import std/strutils
import spoa/utils


var buf: array[10, uint8]

proc fuzz_target(input: uint64) {.exportc.} =
  echo encodeVarint(buf, input)

when isMainModule:
  let input = readAll(stdin)
  try:
    let i = parseInt(input).uint64
    fuzz_target(i)
  except:
    discard