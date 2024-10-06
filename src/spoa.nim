import std/[posix, streams, strutils]
import ba0f3/[logger, hexdump]
import chronos
import spoa/[types, frame, utils]

proc newSpoeAgent(): SpoeAgent =
  new(result)
  result.maxFrameSize = MAX_FRAME_SIZE

proc close*(agent: SpoeAgent) {.async.} =
  discard
  #if not done.finished():
    # Notify server that it's time to stop - some other client could
    # have done this already, so we check with `finished` first
  #  done.complete()
  #  break
  #elif data[0] == '0':
  #  break # Stop reading and close the connection

proc checkProtoVersion(value: SpoeTypedData): bool =
  if value.kind != STRING:
    warn "Error: Invalid data-type for supported versions", kind=value.kind
    return false
  debug "HAProxy supported versions", versions=value.s
  for ver in value.s.split(","):
    if SPOP_VERSION == ver.strip():
      return true

proc checkMaxFrameSize(agent: SpoeAgent, value: SpoeTypedData): bool =
  var maxSize: uint64
  case value.kind
  of INT32:
    maxSize = value.i32.uint64
  of UINT32:
    maxSize = value.u32.uint64
  of INT64:
    maxSize = value.i64.uint64
  of UINT64:
    maxSize = value.u64
  else:
    warn "Error: Invalid data-type for maximum frame size", kind=value.kind
    return false

  if maxSize < agent.maxFrameSize:
    agent.maxFrameSize = maxSize

  debug "HAProxy maximum frame size", maxSize
  result = true

proc checkHealthCheck(agent: SpoeAgent, value: SpoeTypedData): bool =
  if value.kind != BOOLEAN:
    warn "Error: Invalid data-type for healthcheck", kind=value.kind
    return false

  agent.healthcheck = value.b
  debug "HAProxy HELLO healthcheck", hcheck=value.b
  result = true

proc checkCapabilities(agent: SpoeAgent, value: SpoeTypedData): bool =
  if value.kind != STRING:
    warn "Error: Invalid data-type for capabilities", kind=value.kind
    return false
  debug "HAProxy capabilities", cap=value.s
  for cap in value.s.split(","):
    let cap = cap.strip()
    if cap == "pipelining":
      debug "HAProxy supports pipelining"
      agent.pipelining = true
    elif cap == "async":
      debug "Ignoring deprecated support for asynchronous frames"
    elif cap == "fragmentation":
      debug "Ignoring deprecated support for fragmentated frame"
  result = true

proc checkEngineId(agent: SpoeAgent, value: SpoeTypedData): bool =
  if value.kind != STRING:
    warn "Error: Invalid data-type for engine id", kind=value.kind
    return false

  debug "HAProxy engine id", id=value.s
  agent.engineId = value.s

  result = true


proc handleHello(agent: SpoeAgent, header: SpoeFrameHeader, stream: StringStream, frame: SpoeFrame): Future[SpoeFrameError] {.async: (raises: [Exception]).} =
  if (header.flags and SPOE_FRAME_FLAG_FIN) == 0:
    return ERROR_FRAG_NOT_SUPPORTED
  if header.streamId != 0 or header.frameId != 0:
    return ERROR_INVALID
  var
    key: string
    value: SpoeTypedData
  while not stream.atEnd():
    key = stream.readString()
    if key.len == 0:
      return ERROR_INVALID
    if key == "supported-versions":
      value = stream.readTypedData()
      if not checkProtoVersion(value):
        return ERROR_INVALID
    elif key == "max-frame-size":
      value = stream.readTypedData()
      if not agent.checkMaxFrameSize(value):
        return ERROR_INVALID
    elif key == "healthcheck":
      value = stream.readTypedData()
      if not agent.checkHealthCheck(value):
        return ERROR_INVALID
    elif key == "capabilities":
      value = stream.readTypedData()
      if not agent.checkCapabilities(value):
        return ERROR_INVALID
    elif key == "engine-id":
      value = stream.readTypedData()
      if not agent.checkEngineId(value):
        return ERROR_INVALID
    else:
      debug "Skip unsupported K/V item", key


  frame.addKV("version", SPOP_VERSION)
  frame.addKV("max-frame-size", agent.maxFrameSize)
  frame.addKV("capabilities", SPOP_CAPABILITIES)

proc handleConn(agent: SpoeAgent, transport: StreamTransport, done: Future[void]) {.async: (raises: [IOError, OSError, Exception]).} =
  var
    ret: int
    length: uint32
    buffer: pointer
    stream: StringStream
    error = ERROR_NONE
    header: SpoeFrameHeader

  # Handle a single remote connection
  try:
    debug "Incoming connection from ", remoteAddr=transport.remoteAddress()
    while true:
      ret = await transport.readOnce(addr length, sizeof(length))
      echo "ret ", ret
      if ret != 4:
        error = ERROR_IO
        break
      length = ntohl(length)
      echo "frameLength ", length
      if length > MAX_FRAME_SIZE:
        error = ERROR_TOO_BIG
        break

      buffer = alloc(length)
      ret = await transport.readOnce(buffer, length.int)
      hexdump(buffer, length.int)
      stream = newStringStream()
      stream.writeData(buffer, length.int)
      stream.setPosition(0)
      dealloc(buffer)

      header = stream.readFrameHeader()

      var frame = newFrame(AGENT_HELLO)

      case header.kind:
      of HAPROXY_HELLO:
        error = await agent.handleHello(header, stream, frame)

      else:
        debug "HAProxy request", kind=header.kind
      if error != ERROR_NONE:
        break

      var
        data = newStringStream()
        length = htonl(data.writeFrame(frame).uint32)
      data.setPosition(0)
      var d = data.readAll()
      discard  await transport.write(addr length, 4)
      echo "Sent ",  await transport.write(d), " bytes"
      hexdump(d.cstring, d.len)

    if error == ERROR_IO:
      warn "Close the client socket because of I/O errors"
    else:
      warn "Disconnect frame sent", reason=error
      #await transport.write(data & "\n"), " bytes"
  except CancelledError:
    raiseAssert "No cancellations in this example"
  except TransportError as exc:
    error "Connection problem! ", msg=exc.msg
  finally:
    # Connections must always be closed to avoid resource leaks
    await transport.closeWait()


proc run*(agent: SpoeAgent) {.async: (raises: [Exception]).} =
  let
    server = createStreamServer(initTAddress("0.0.0.0:12345"), flags = {ReuseAddr})

  debug "Accepting connections on ", localAddr=server.local
  let done = Future[void].init()
  try:
    while true:
      let accept = server.accept()
      discard await race(accept, done)
      if done.finished(): break
      asyncSpawn agent.handleConn(accept.read(), done)
  finally:
    await server.closeWait()


when isMainModule:
  initLogger()
  let agent = newSpoeAgent()
  waitFor agent.run()