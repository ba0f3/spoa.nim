import std/[posix, streams]
import chronos/streams/asyncstream

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

proc decodeVarint*(reader: AsyncStreamReader, value: ptr uint64, bytesRead: ptr uint64): Future[int] {.async: (raises: [AsyncStreamError, CancelledError]).} =
  ##[
  Decodes a variable length integer from a stream into an unsigned 64-bit integer.
  Returns: The number of bytes read on success or -1 if not enough data was available in the stream.
  Arguments:
    stream: An AsyncStreamReader object to read the varint from.
    value: An output parameter to store the decoded varint value into.
  ]##
  value[] = 0
  if reader.closed: return -1

  try:
    await reader.readExactly(value, 1)
    inc(bytesRead[])

    if value[] < 240: return 1

    while true:
      if reader.closed:
        value[] = 0
        return -1

      var val: uint8
      await reader.readExactly(addr val, 1)

      inc(bytesRead[])
      inc(result)
      let tmp = val.uint64 shl (4 + 7 * (result - 1))
      value[].inc(tmp)
      if val < 128:
        break
    inc(result)
  except AsyncStreamError, CancelledError:
    value[] = 0
    return -1


proc readString*(reader: AsyncStreamReader, bytesRead: ptr uint64): Future[string] {.async.}  =
  var
    length: uint64
    size = await reader.decodeVarint(addr length, bytesRead)
  if size != -1:
    result = newString(length.int)
    await reader.readExactly(result.cstring, length.int)
    inc(bytesRead[], length)

proc writeString*(stream: StringStream, str: string) =
  var
    buf: array[10, uint8]
    strLen = str.len
    ret = encodeVarint(buf, strLen.uint64)
  stream.writeData(addr buf, ret)
  stream.writeData(str.cstring, str.len)