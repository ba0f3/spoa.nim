from std/strutils import split, strip
import std/times
import chronos, chronicles
import ./[common, frame, message, request, typeddata, utils, pool]

type
  SpoeClient* = ref object
    agent*: SpoeAgent
    engineId*: string
    pipelining*: bool
    healthcheck*: bool
    maxFrameSize*: uint32
    clientId*: int

    transp*: StreamTransport
    reader*: AsyncStreamReader
    writer*: AsyncStreamWriter

var
  clientPool* = Pool[SpoeClient].new()
  clientId* = 0


proc init*(client: SpoeClient, transp: StreamTransport) =
  client.transp = transp
  client.reader = newAsyncStreamReader(transp)
  client.writer = newAsyncStreamWriter(transp)


proc new*(ctype: typedesc[SpoeClient], agent: SpoeAgent, transp: StreamTransport): SpoeClient =
  result = SpoeClient(
    agent: agent,
    maxFrameSize: agent.maxFrameSize
  )
  inc(clientId)
  result.clientId = clientId
  result.init(transp)

proc closed*(client: SpoeClient): bool = client.transp.closed

proc close*(client: SpoeClient) =
  if not client.reader.closed:
    client.reader.close()
  if not client.writer.closed():
    client.writer.close()
  if client.transp.closed():
    client.transp.close()

proc disconnect*(client: SpoeClient, error: SpoeFrameError = ERROR_NONE, message = "") {.async: (raises: [CatchableError]).} =
  if error != ERROR_NONE:
    if error == ERROR_IO:
      warn "Close the client socket because of I/O errors", id=client.clientId
    else:
      warn "Close connection due to error", id=client.clientId, error

  debug "Agent disconnect", id=client.clientId, engineId=client.engineId, error, message

  var frame = SpoeFrame.new(AGENT_DISCONNECT)
  frame.addKV("status-code", error.uint32)
  if message.len > 0:
    frame.addKV("message", message)
  await client.writer.write(frame)
  client.close()

proc checkProtoVersion(client: SpoeClient, value: SpoeTypedData): bool =
  if not value.isString:
    warn "Error: Invalid data-type for supported versions", id=client.clientId
    return false
  let versions = value.getStr()
  debug "HAProxy supported versions", id=client.clientId, versions
  for ver in versions.split(","):
    if SPOP_VERSION == ver.strip():
      return true

proc checkMaxFrameSize(client: SpoeClient, value: SpoeTypedData): bool =
  var maxSize: uint64
  if value.isUnsignedInt:
    maxSize = value.getBiggestUint()
  else:
    warn "Error: Invalid data-type for maximum frame size", id=client.clientId
    return false

  debug "HAProxy maximum frame size", id=client.clientId, maxSize

  if client.maxFrameSize > maxSize:
    debug "Set max-frame-size", id=client.clientId, oldSize=client.maxFrameSize, newSize=maxSize
    client.maxFrameSize = maxSize.uint32

  result = true

proc checkHealthCheck(client: SpoeClient, value: SpoeTypedData): bool =
  if not value.isBool:
    warn "Error: Invalid data-type for healthcheck", id=client.clientId
    return false

  client.healthcheck = value.getBool()
  debug "HAProxy healthcheck", id=client.clientId, hcheck=client.healthcheck
  result = true

proc checkCapabilities(client: SpoeClient, value: SpoeTypedData): bool =
  if not value.isString:
    warn "Error: Invalid data-type for capabilities", id=client.clientId
    return false
  let caps = value.getStr()
  debug "HAProxy capabilities", id=client.clientId, caps
  for cap in caps.split(","):
    let cap = cap.strip()
    if cap == "pipelining":
      if client.agent.pipelining:
        debug "HAProxy supports pipelining", id=client.clientId
        client.pipelining = true
      else:
        debug "HAProxy supports pipelining, but disabled by agent", id=client.clientId
        client.pipelining = false
    elif cap == "async":
      debug "Agent does not support asynchronous frames", id=client.clientId
    elif cap == "fragmentation":
      debug "Agent does not support fragmentated frame", id=client.clientId
  result = true

proc checkEngineId(client: SpoeClient, value: SpoeTypedData): bool =
  if not value.isString:
    warn "Error: Invalid data-type for engine id", id=client.clientId
    return false

  client.engineId = value.getStr()
  result = true

proc handleHello(client: SpoeClient, header: SpoeFrameHeader): Future[SpoeFrameError] {.async.} =
  if (header.flags and SPOE_FRAME_FLAG_FIN) == 0:
    return ERROR_FRAG_NOT_SUPPORTED
  if header.streamId != 0 or header.frameId != 0:
    return ERROR_INVALID

  info "HAProxy HELLO frame", id=client.clientId, flags=header.flags

  var
    key: string
    value: SpoeTypedData

  while header.bytesRead < header.length:
    key = await client.reader.readString(addr header.bytesRead)
    if key.len == 0:
      return ERROR_INVALID
    if key == "supported-versions":
      value = await client.reader.readTypedData(addr header.bytesRead)
      if not client.checkProtoVersion(value):
        return ERROR_BAD_VSN
    elif key == "max-frame-size":
      value = await client.reader.readTypedData(addr header.bytesRead)
      if not client.checkMaxFrameSize(value):
        return ERROR_BAD_FRAME_SIZE
    elif key == "healthcheck":
      value = await client.reader.readTypedData(addr header.bytesRead)
      if not client.checkHealthCheck(value):
        return ERROR_INVALID
    elif key == "capabilities":
      value = await client.reader.readTypedData(addr header.bytesRead)
      if not client.checkCapabilities(value):
        return ERROR_NO_CAP
    elif key == "engine-id":
      value = await client.reader.readTypedData(addr header.bytesRead)
      if not client.checkEngineId(value):
        return ERROR_INVALID
    else:
      debug "Skip unsupported K/V item", id=client.clientId, key
  var frame = SpoeFrame.new(AGENT_HELLO)
  frame.addKV("version", SPOP_VERSION)
  frame.addKV("max-frame-size", client.maxFrameSize)
  if client.pipelining:
    frame.addKV("capabilities", SPOP_CAPABILITIES)
    debug "Sending Agent HELLO", id=client.clientId, version=SPOP_VERSION, maxFrameSize=client.maxFrameSize, capabilities=SPOP_CAPABILITIES
  else:
    debug "Sending Agent HELLO", id=client.clientId, version=SPOP_VERSION, maxFrameSize=client.maxFrameSize

  await client.writer.write(frame)
  if client.healthcheck:
    debug "Close connection after healthcheck", id=client.clientId
    client.close()


proc handleNotify(client: SpoeClient, header: SpoeFrameHeader): Future[SpoeFrameError] {.async.} =
  if (header.flags and SPOE_FRAME_FLAG_FIN) == 0:
    return ERROR_FRAG_NOT_SUPPORTED
  elif header.frameId == 0:
    return ERROR_FRAMEID_NOTFOUND

  var
    t = now()
    req = SpoeRequest.new(header.streamId, header.frameId)
    msgCount = 0

  info "HAProxy NOTIFY frame", id=client.clientId, streamId=header.streamId, frameId=header.frameId
  while header.bytesRead < header.length:
    let message = await client.reader.readMessage(addr header.bytesRead)
    debug "Processing message", id=client.clientId, name=message.name, nbArgs=message.list.len
    req.addMessage(message)
    inc(msgCount)

  try:
    client.agent.handler(req)
  except:
    error "Failed to execute handler", msg=getCurrentExceptionMsg()

  debug "Preparing Agent ACK frame", id=client.clientId

  var frame = SpoeFrame.new(ACK)
  frame.streamId = header.streamId
  frame.frameId = header.frameId

  for action in req.actions:
    debug "Add action", id=client.clientId, kind=action.kind, scope=action.scope, name=action.name, value=action.value
    frame.actions.add(action)

  await client.writer.write(frame)

  let processingTime = (now() - t).inMilliseconds
  info "Sent ACK frame", id=client.clientId, streamId=header.streamId, frameId=header.frameId, actionCount=frame.actions.len, processingTime=processingTime

proc handleDisconnect(client: SpoeClient, header: SpoeFrameHeader): Future[SpoeFrameError] {.async.} =
  if (header.flags and SPOE_FRAME_FLAG_FIN) == 0:
    return ERROR_FRAG_NOT_SUPPORTED
  if header.streamId != 0 or header.frameId != 0:
    return ERROR_INVALID

  var
    key: string
    value: SpoeTypedData
    statusCode: uint
    message: string

  while header.bytesRead < header.length:
    key = await client.reader.readString(addr header.bytesRead)
    if key.len == 0:
      return ERROR_INVALID
    if key == "status-code":
      value = await client.reader.readTypedData(addr header.bytesRead)
      statusCode = value.getUint()
    elif key == "message":
      value = await client.reader.readTypedData(addr header.bytesRead)
      message = value.getStr()
    else:
      debug "Skip unsupported K/V item", id=client.clientId, key

  info "HAproxy DISCONNECT frame", id=client.clientId, statusCode, message
  result = ERROR_NONE

proc handleConnection*(client: SpoeClient) {.async.} =
  var
    #header: SpoeFrameHeader
    error: SpoeFrameError

  try:
    while not client.closed:
      if client.reader.atEof():
        error = ERROR_IO
        break
      let header = await client.reader.readFrameHeader()
      if header.length > client.maxFrameSize:
        error = ERROR_TOO_BIG
        break

      case header.kind:
      of HAPROXY_HELLO:
        error = await client.handleHello(header)
      of HAPROXY_DISCONNECT:
        error = await client.handleDisconnect(header)
        break
      of NOTIFY:
        error = await client.handleNotify(header)
      else:
        debug "HAProxy requests unsupported frame type", id=client.clientId, kind=header.kind
        error = ERROR_INVALID
        break

  except AsyncStreamIncompleteError, AsyncStreamWriteEOFError:
    error "Stream error", msg=getCurrentExceptionMsg()
    error = ERROR_RES
  except CatchableError:
    error "Unknown error", msg=getCurrentExceptionMsg()
    error = ERROR_RES
  finally:
    await client.disconnect(error)
