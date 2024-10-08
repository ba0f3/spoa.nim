import std/[posix, streams]
import chronos/streams/asyncstream
import ba0f3/hexdump
import kv, message, action, typeddata, utils

type
  SpoeFrameKind* = enum
    UNSET
    HAPROXY_HELLO
    HAPROXY_DISCONNECT
    NOTIFY
    AGENT_HELLO = 101
    AGENT_DISCONNECT
    ACK

  SpoeFrameHeader* = object
    length*: uint32
    bytesRead*: uint64
    kind*: SpoeFrameKind
    flags*: uint32
    streamId*: uint64
    frameId*: uint64

  SpoeFrame* = ref object
    kind*: SpoeFrameKind
    flags*: uint32
    streamId*: uint64
    frameId*: uint64
    messages*: seq[SpoeMessage]
    actions*: seq[SpoeAction]
    list*: seq[SpoeKV]

proc new*(ctype: typedesc[SpoeFrame], kind: SpoeFrameKind): SpoeFrame =
  result = SpoeFrame(
    kind: kind,
    flags: 0x1,
    streamId: 0,
    frameId: 0
  )

proc addMessage*(frame: SpoeFrame, name: string, kv: seq[SpoeKV]) =
  let message = SpoeMessage(name: name, list: kv)
  frame.messages.add(message)

proc addAction*(frame: SpoeFrame, kind: SpoeActionKind, kv: seq[SpoeKV]) =
  let action = SpoeAction(kind: kind, list: kv)
  frame.actions.add(action)

proc addKV*(frame: SpoeFrame, key: string, value: auto) =
  frame.list.add(SpoeKV(key: key, value: toTypedData(value)))

proc readFrameHeader*(reader: AsyncStreamReader): Future[SpoeFrameHeader] {.async.} =
  ## Returns header's size
  await reader.readExactly(addr result.length, sizeof(uint32))
  result.length = ntohl(result.length)

  result.bytesRead = 0
  await reader.readExactly(addr result.kind, sizeof(SpoeFrameKind))
  inc(result.bytesRead, sizeof(SpoeFrameKind))
  await reader.readExactly(addr result.flags, sizeof(uint32))
  inc(result.bytesRead, sizeof(uint32))

  result.flags = ntohl(result.flags)

  var tmp: uint64
  discard await reader.decodeVarint(addr tmp, addr result.bytesRead)
  result.streamId = tmp
  discard await reader.decodeVarint(addr tmp, addr result.bytesRead)
  result.frameId = tmp

proc write*(writer: AsyncStreamWriter, frame: SpoeFrame) {.async.} =
  var
    buf: array[10, uint8]
    ret: int
    flags = htonl(frame.flags)
    frameLength: uint32

  var stream = newStringStream()
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

  frameLength = htonl(stream.getPosition().uint32)
  stream.setPosition(0)
  let data = stream.readAll()
  hexdump(data.cstring, ntohl(frameLength).int)
  await writer.write(addr frameLength, sizeof(uint32))
  await writer.write(data)
  await writer.finish()

