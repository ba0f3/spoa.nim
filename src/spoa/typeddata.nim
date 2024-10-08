import std/[posix, streams]
from std/strutils import toHex
import chronos/streams/asyncstream
import common, utils

type
  SpoeTypedData* = object
    case kind*: SpoeDataKind
    of BOOLEAN: b*: bool
    of INT32: i32*: int32
    of UINT32: u32*: uint32
    of INT64: i64*: int64
    of UINT64: u64*: uint64
    of IPV4: v4*: InAddr
    of IPV6: v6*: In6Addr
    of STRING, BINARY:
      s*: string
    else: discard

proc `$`*(data: SpoeTypedData): string =
  case data.kind
  of NULL:
    result = "nil"
  of BOOLEAN:
    result = $data.b
  of INT32:
    result = $data.i32 & "'i32"
  of UINT32:
    result = $data.u32 & "'u32"
  of INT64:
    result = $data.i64 & "'i64"
  of UINT64:
    result = $data.u64 & "'u64"
  of IPV4:
    let ip = inet_ntoa(data.v4)
    result = $ip
  of IPV6:
    var buff: array[0..255, char]
    let r = inet_ntop(AF_INET6, addr data.v6, cast[cstring](addr buff[0]), buff.len.int32)
    result = $r
  of STRING:
    result = "\"" & data.s & "\""
  of BINARY:
    result = toHex(data.s)



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

proc readTypedData*(reader: AsyncStreamReader, bytesRead: ptr uint64): Future[SpoeTypedData] {.async.} =
  var tmp: uint8
  await reader.readExactly(addr tmp, 1)
  inc(bytesRead[])

  let
    kind = SpoeDataKind(tmp and 0x0F)
    flags = tmp shr 4

  var temp: uint64
  case kind
  of NULL:
    result = SpoeTypedData(kind: kind)
  of BOOLEAN:
    result = SpoeTypedData(kind: kind, b: (flags and 0x01) > 0)
  of INT32:
    discard await reader.decodeVarint(addr temp, bytesRead)
    result = SpoeTypedData(kind: kind, i32: temp.int32)
  of UINT32:
    discard await reader.decodeVarint(addr temp, bytesRead)
    result = SpoeTypedData(kind: kind, u32: temp.uint32)
  of INT64:
    discard await reader.decodeVarint(addr temp, bytesRead)
    result = SpoeTypedData(kind: kind, i64: temp.int64)
  of UINT64:
    discard await reader.decodeVarint(addr temp, bytesRead)
    result = SpoeTypedData(kind: kind, u64: temp)
  of IPV4:
    var ip: InAddr
    await reader.readExactly(addr ip, sizeof(InAddr))
    inc(bytesRead[], sizeof(InAddr))
    result = SpoeTypedData(kind: kind, v4: ip)
  of IPV6:
    var ip: In6Addr
    await reader.readExactly(addr ip, sizeof(In6Addr))
    inc(bytesRead[], sizeof(In6Addr))
    result = SpoeTypedData(kind: kind, v6: ip)
  of STRING, BINARY:
    result = SpoeTypedData(kind: kind, s: await reader.readString(bytesRead))

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
