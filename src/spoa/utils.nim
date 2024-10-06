import std/[posix, streams]
import types


proc encodeVarint*(buf: var array[10, uint8], n: uint64): int =
  if n < 240:
    buf[0] = n.uint8
    return 1

  buf[0] = n.uint8 or 240

  var u = (n - 240) shr 4
  result = 1
  while u >= 128:
    buf[result] = u.uint8 or 128
    u = (u - 128) shr 7
    inc(result)
  buf[result] = u.uint8
  inc(result)

proc decodeVarint*(stream: StringStream, value: var uint64): int =
  ##[
  Decodes a variable length integer from a stream into an unsigned 64-bit integer.
  Returns: The number of bytes read on success or -1 if not enough data was available in the stream.
  Arguments:
    stream: A StringStream object to read the varint from.
    value: An output parameter to store the decoded varint value into.
  ]##

  value = 0
  if stream.atEnd():
    return -1

  value = stream.readUint8().uint64
  if value < 240:
    return 1

  while true:
    if stream.atEnd():
      value = 0
      return -1

    let val = stream.readUint8()
    inc(result)
    let tmp = val.uint64 shl (4 + 7 * (result - 1))
    value.inc(tmp)
    if val < 128:
      break
  inc(result)


proc readString*(stream: StringStream): string =
  var
    length: uint64
    size = stream.decodeVarint(length)
  if size != -1:
    result = stream.readStr(length.int)

proc writeString*(stream: StringStream, str: string) =
  var
    buf: array[10, uint8]
    strLen = str.len
    ret = encodeVarint(buf, strLen.uint64)
  stream.writeData(addr buf, ret)
  stream.writeData(str.cstring, strLen)

proc toTypedData*(v: auto): SpoeTypedData =
  when v is bool:
    result = SpoeTypedData(kind: BOOLEAN, b: v)
  elif v is int32:
    result = SpoeTypedData(kind: INT32, i32: v)
  elif v is uint32:
    result = SpoeTypedData(kind: UINT32, u32: v)
  elif v is int64:
    result = SpoeTypedData(kind: INT64, i64: v)
  elif v is uint64:
    result = SpoeTypedData(kind: UINT64, u64: v)
  elif v is InAddr:
    result = SpoeTypedData(kind: IPV4, v4: v)
  elif v is In6Addr:
    result = SpoeTypedData(kind: IPV6, v6: v)
  elif v is string:
    result = SpoeTypedData(kind: STRING, s: v)
  else:
    raise newException(ValueError, "Unsupported data type " & v.type)


proc readTypedData*(stream: StringStream): SpoeTypedData =
  let
    tmp = stream.readUint8()
    kind = SpoeDataKind(tmp and 0x0F)
    flags = tmp shr 4

  var temp: uint64
  case kind
  of NULL:
    result = SpoeTypedData(kind: kind)
  of BOOLEAN:
    result = SpoeTypedData(kind: kind, b: (flags and 0x01) > 0)
  of INT32:
    discard stream.decodeVarint(temp)
    result = SpoeTypedData(kind: kind, i32: temp.int32)
  of UINT32:
    discard stream.decodeVarint(temp)
    result = SpoeTypedData(kind: kind, u32: temp.uint32)
  of INT64:
    discard stream.decodeVarint(temp)
    result = SpoeTypedData(kind: kind, i64: temp.int64)
  of UINT64:
    discard stream.decodeVarint(temp)
    result = SpoeTypedData(kind: kind, u64: temp)
  of IPV4:
    var ip: InAddr
    discard stream.readData(addr ip, sizeof(InAddr))
    result = SpoeTypedData(kind: kind, v4: ip)
  of IPV6:
    var ip: In6Addr
    discard stream.readData(addr ip, sizeof(In6Addr))
    result = SpoeTypedData(kind: kind, v6: ip)
  of STRING, BINARY:
    result = SpoeTypedData(kind: kind, s: stream.readString())

proc writeTypedData*(stream: StringStream, data: SpoeTypedData) =
  var
    buf: array[10, uint8]
    ret: int

  if data.kind != BOOLEAN:
    buf[0] = data.kind.uint8
  else:
    buf[0] = 0x1
    buf[0] = (buf[0] shl 4) +  data.kind.uint8

  stream.writeData(addr buf[0], 1)


  case data.kind
  #of NULL:
  #  buf[0] = 0
  #  stream.writeData(addr buf, 1)
  #of BOOLEAN:
  #  if data.b:
  #    tmp = tmp + 0x1
  of INT32:
    ret = encodeVarint(buf, data.i32.uint64)
    stream.writeData(addr buf, ret)
  of UINT32:
    ret = encodeVarint(buf, data.u32.uint64)
    stream.writeData(addr buf, ret)
  of INT64:
    ret = encodeVarint(buf, data.i64.uint64)
    stream.writeData(addr buf, ret)
  of UINT64:
    ret = encodeVarint(buf, data.u64)
    stream.writeData(addr buf, ret)
  of IPV4:
    stream.writeData(addr data.v4, 4)
  of IPV6:
    stream.writeData(addr data.v6, 16)
  of STRING, BINARY:
    stream.writeString(data.s)
  else:
    discard

proc writeKV*(stream: StringStream, kv: SpoeKV) =
  stream.writeString(kv.key)
  stream.writeTypedData(kv.value)

proc readFrameHeader*(stream: StringStream): SpoeFrameHeader =
  #discard stream.readData(addr result, sizeof(SpoeFrameHeader))
  result.kind = cast[SpoeFrameKind](stream.readUint8())
  result.flags = ntohl(stream.readUint32())
  var tmp: uint64
  discard stream.decodeVarint(tmp)
  result.streamId = tmp
  discard stream.decodeVarint(tmp)
  result.frameId = tmp