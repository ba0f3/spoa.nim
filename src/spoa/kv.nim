import std/streams
import chronos/streams/asyncstream
import ba0f3/logger
import typeddata, utils

type
   SpoeKV* = object
    key*: string
    value*: SpoeTypedData

proc readKV*(reader: AsyncStreamReader, bytesRead: ptr uint64): Future[SpoeKV] {.async: (raises: [Exception]).} =
  let
    key = await reader.readString(bytesRead)
    value = await reader.readTypedData(bytesRead)

  debug "kv", key, value

  result = SpoeKV(
    key: key,
    value: value
  )

proc writeKV*(stream: StringStream, kv: SpoeKV) =
  stream.writeString(kv.key)
  stream.writeTypedData(kv.value)

