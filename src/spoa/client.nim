from std/strutils import split, strip
import chronos
import ba0f3/logger
import common, frame, message, request, typeddata, utils



type
  SpoeClient* = ref object
    agent*: SpoeAgent
    engineId*: string
    pipelining*: bool
    healthcheck*: bool
    maxFrameSize*: uint32

    transp*: StreamTransport
    reader*: AsyncStreamReader
    writer*: AsyncStreamWriter

proc closed*(client: SpoeClient): bool =
  (client.reader.closed and client.writer.closed) or client.transp.closed

proc disconnect*(client: SpoeClient, error: SpoeFrameError = ERROR_NONE, message = "") {.async: (raises: [Exception]).} =

  if error != ERROR_NONE:
    if error == ERROR_IO:
      warn "Close the client socket because of I/O errors", remote=client.transp.remoteAddress
    else:
      warn "Disconnect frame sent", remote=client.transp.remoteAddress, reason=error

    var frame = SpoeFrame.new(AGENT_DISCONNECT)
    frame.addKV("status-code", error.uint32)
    frame.addKV("message", message)
    await client.writer.write(frame)

  if not(client.reader.isNil) and not(client.reader.closed()):
    await client.reader.closeWait()
  if not(client.writer.isNil) and not(client.writer.closed()):
    await client.writer.closeWait()
  if not(client.transp.closed()):
    await client.transp.closeWait()


proc checkProtoVersion(value: SpoeTypedData): bool =
  if value.kind != STRING:
    warn "Error: Invalid data-type for supported versions", kind=value.kind
    return false
  debug "HAProxy supported versions", versions=value.s
  for ver in value.s.split(","):
    if SPOP_VERSION == ver.strip():
      return true

proc checkMaxFrameSize(client: SpoeClient, value: SpoeTypedData): bool =
  var maxSize: uint32
  case value.kind
  of INT32:
    maxSize = value.i32.uint32
  of UINT32:
    maxSize = value.u32
  of INT64:
    maxSize = value.i64.uint32
  of UINT64:
    maxSize = value.u64.uint32
  else:
    warn "Error: Invalid data-type for maximum frame size", kind=value.kind
    return false

  debug "HAProxy maximum frame size", maxSize

  if client.maxFrameSize > maxSize:
    debug "Set max-frame-size", oldSize=client.maxFrameSize, newSize=maxSize
    client.maxFrameSize = maxSize

  result = true

proc checkHealthCheck(client: SpoeClient, value: SpoeTypedData): bool =
  if value.kind != BOOLEAN:
    warn "Error: Invalid data-type for healthcheck", kind=value.kind
    return false

  debug "HAProxy HELLO healthcheck", hcheck=value.b
  client.healthcheck = value.b
  result = true

proc checkCapabilities(client: SpoeClient, value: SpoeTypedData): bool =
  if value.kind != STRING:
    warn "Error: Invalid data-type for capabilities", kind=value.kind
    return false
  debug "HAProxy capabilities", cap=value.s
  for cap in value.s.split(","):
    let cap = cap.strip()
    if cap == "pipelining":
      debug "HAProxy supports pipelining"
      client.pipelining = true
    elif cap == "async":
      debug "Ignoring deprecated support for asynchronous frames"
    elif cap == "fragmentation":
      debug "Ignoring deprecated support for fragmentated frame"
  result = true

proc checkEngineId(client: SpoeClient, value: SpoeTypedData): bool =
  if value.kind != STRING:
    warn "Error: Invalid data-type for engine id", kind=value.kind
    return false

  debug "HAProxy engine id", id=value.s
  client.engineId = value.s

  result = true

proc handleHello(client: SpoeClient, header: SpoeFrameHeader): Future[SpoeFrameError] {.async: (raises: [Exception]).} =
  if (header.flags and SPOE_FRAME_FLAG_FIN) == 0:
    return ERROR_FRAG_NOT_SUPPORTED
  if header.streamId != 0 or header.frameId != 0:
    return ERROR_INVALID

  var
    key: string
    value: SpoeTypedData

  #while not client.reader.atEof() and not client.reader.closed() :
  while header.bytesRead < header.length:
    key = await client.reader.readString(addr header.bytesRead)
    if key.len == 0:
      return ERROR_INVALID
    if key == "supported-versions":
      value =await client.reader.readTypedData(addr header.bytesRead)
      if not checkProtoVersion(value):
        return ERROR_INVALID
    elif key == "max-frame-size":
      value = await client.reader.readTypedData(addr header.bytesRead)
      if not client.checkMaxFrameSize(value):
        return ERROR_INVALID
    elif key == "healthcheck":
      value = await client.reader.readTypedData(addr header.bytesRead)
      if not client.checkHealthCheck(value):
        return ERROR_INVALID
    elif key == "capabilities":
      value = await client.reader.readTypedData(addr header.bytesRead)
      if not client.checkCapabilities(value):
        return ERROR_INVALID
    elif key == "engine-id":
      value = await client.reader.readTypedData(addr header.bytesRead)
      if not client.checkEngineId(value):
        return ERROR_INVALID
    else:
      debug "Skip unsupported K/V item", key


  var frame = SpoeFrame.new(AGENT_HELLO)
  frame.addKV("version", SPOP_VERSION)
  frame.addKV("max-frame-size", client.maxFrameSize)
  frame.addKV("capabilities", SPOP_CAPABILITIES)
  await client.writer.write(frame)
  if client.healthcheck:
    await client.disconnect()

proc handleNotify(client: SpoeClient, header: SpoeFrameHeader): Future[SpoeFrameError] {.async: (raises: [Exception]).} =
  if (header.flags and SPOE_FRAME_FLAG_FIN) == 0:
    return ERROR_FRAG_NOT_SUPPORTED
  elif header.frameId == 0:
    return ERROR_FRAMEID_NOTFOUND

  debug "HAProxy notify", streamId=header.streamId, frameId=header.frameId

  var messages: seq[SpoeMessage]
  while header.bytesRead < header.length:
    let message = await client.reader.readMessage(addr header.bytesRead)
    messages.add(message)

  var req = SpoeRequest.new(header.streamId, header.frameId)
  client.agent.handler(req)

  var frame = SpoeFrame.new(ACK)
  frame.streamId = header.streamId
  frame.frameId = header.frameId
  frame.actions = req.actions

  debug "Sending ACK response frame", streamId=header.streamId, frameId=header.frameId
  await client.writer.write(frame)

proc handleDisconnect(client: SpoeClient, header: SpoeFrameHeader): Future[SpoeFrameError] {.async: (raises: [Exception]).} =
  if (header.flags and SPOE_FRAME_FLAG_FIN) == 0:
    return ERROR_FRAG_NOT_SUPPORTED
  if header.streamId != 0 or header.frameId != 0:
    return ERROR_INVALID

  var
    key: string
    value: SpoeTypedData
    statusCode: uint32
    message: string

  while header.bytesRead < header.length:
    key = await client.reader.readString(addr header.bytesRead)
    if key.len == 0:
      return ERROR_INVALID
    if key == "status-code":
      value = await client.reader.readTypedData(addr header.bytesRead)
      statusCode = value.u32
    elif key == "message":
      value = await client.reader.readTypedData(addr header.bytesRead)
      message = value.s
    else:
      debug "Skip unsupported K/V item", key

  debug "HAProxy disconnect", code=statusCode, msg=message
  await client.disconnect()


proc new*(ctype: typedesc[SpoeClient], agent: SpoeAgent, transp: StreamTransport): SpoeClient =
  result = SpoeClient(
    agent: agent,
    maxFrameSize: agent.maxFrameSize,
    transp: transp,
    reader: newAsyncStreamReader(transp),
    writer: newAsyncStreamWriter(transp)
  )

proc handleConnection*(client: SpoeClient) {.async: (raises: [Exception]).} =
  var
    header: SpoeFrameHeader
    error: SpoeFrameError

  while not client.closed:
    if client.reader.atEof():
      await client.disconnect(ERROR_IO)
      return
    try:
      header = await client.reader.readFrameHeader()
      if header.length > client.maxFrameSize:
        await client.disconnect(ERROR_TOO_BIG)
        return

      case header.kind:
      of HAPROXY_HELLO:
        error = await client.handleHello(header)
        if error != ERROR_NONE:
          await client.disconnect(error)
      of HAPROXY_DISCONNECT:
        error = await client.handleDisconnect(header)
      of NOTIFY:
        error = await client.handleNotify(header)
      else:
        debug "HAProxy request", kind=header.kind
        await client.disconnect(ERROR_INVALID, "Unsupported frame type " & $header.kind)

    except AsyncStreamIncompleteError, AsyncStreamWriteEOFError:
      error "Stream error", msg=getCurrentExceptionMsg()
    finally:
      if error != ERROR_NONE:
        await client.disconnect(error)


        #await transport.write(data & "\n"), " bytes"


