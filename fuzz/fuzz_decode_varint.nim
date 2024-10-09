import std/streams


proc decodeVarint(input: string): uint64 =
  result = 0

  let stream = newStringStream(input)
  var idx = 0

  result = stream.readUint8().uint64
  if result < 240: return 1

  while true:
    if stream.atEnd:
      result = 0
      break

    var val = stream.readUint8()
    inc(idx)
    let tmp = val.uint64 shl (4 + 7 * (idx - 1))
    result.inc(tmp)
    if val < 128:
      break


proc fuzz_target(input: string) {.exportc.} =
  echo decodeVarint(input)

when isMainModule:
  let input = readAll(stdin)
  fuzz_target(input)
