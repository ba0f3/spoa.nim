import std/[posix, streams]
import types, utils

proc newFrame*(kind: SpoeFrameKind): SpoeFrame =
  new(result)
  result.kind = kind
  result.flags = 0x1
  #result.maxFrameSize = maxFrameSize
  result.streamId = 0
  result.frameId = 0

proc addMessage*(frame: SpoeFrame, name: string, kv: seq[SpoeKV]) =
  let message = SpoeMessage(name: name, list: kv)
  frame.messages.add(message)

proc addAction*(frame: SpoeFrame, kind: SpoeActionKind, kv: seq[SpoeKV]) =
  let action = SpoeAction(kind: kind, list: kv)
  frame.actions.add(action)

proc addKV*(frame: SpoeFrame, key: string, value: auto) =
  frame.list.add(SpoeKV(key: key, value: toTypedData(value)))

proc writeFrame*(stream: StringStream, frame: SpoeFrame): int =
  let lastPos = stream.getPosition()

  var
    buf: array[10, uint8]
    ret: int
    frameLength: uint32 = 0
    flags = htonl(frame.flags)

  #stream.writeData(addr frameLength, 4)
  stream.writeData(addr frame.kind, sizeof(SpoeFrameKind))
  stream.writeData(addr flags, sizeof(uint32))

  ret = encodeVarint(buf, frame.streamId)
  stream.writeData(addr buf, ret)

  ret = encodeVarint(buf, frame.frameId)
  stream.writeData(addr buf, ret)

  for message in frame.messages:
    # write name
    stream.writeString(message.name)

    # write nb-args
    var argsLen = message.list.len
    stream.writeData(addr argsLen, 1)

    # write kv-list
    for kv in message.list:
      stream.writeKV(kv)

  for action in frame.actions:
    # write active-type
    stream.writeData(addr action.kind, 1)

    # write nb-args
    var argsLen = action.list.len
    stream.writeData(addr argsLen, 1)

    # write kv-list
    for kv in action.list:
      stream.writeKV(kv)

  # write kv-list
  for kv in frame.list:
    stream.writeKV(kv)

  let savePos = stream.getPosition()
  #stream.setPosition(lastPos)
  result = savePos - lastPos
  #frameLength = htonl(result.uint32 - 4)

  # write frame-length
  #stream.setPosition(lastPos)
  #stream.writeData(addr frameLength, 4)

  #stream.setPosition(savePos)