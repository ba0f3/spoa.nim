import chronos/streams/asyncstream
import ./[kv, utils]

type
  SpoeMessage* = ref object
    name*: string
    list*: seq[SpoeKV]

proc new*(ctype: typedesc[SpoeMessage]): SpoeMessage =
  result = SpoeMessage()

proc readMessage*(reader: AsyncStreamReader, bytesRead: ptr uint64): Future[SpoeMessage] {.async.} =
  result = SpoeMessage.new()
  result.name = await reader.readString(bytesRead)

  var nbArgs: uint8
  await reader.readExactly(addr nbArgs, 1)
  inc(bytesRead[])

  while nbArgs > 0:
    result.list.add(await reader.readKV(bytesRead))
    dec(nbArgs)
