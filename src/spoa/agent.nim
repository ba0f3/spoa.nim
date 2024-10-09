import chronos, chronicles

import ./[common, client, pool]

proc new*(ctype: typedesc[SpoeAgent], handler: SpoeHandler, address = "127.0.0.1:12345", maxConn = 10, pipelining = true): SpoeAgent =
  result = SpoeAgent(
    address: address,
    pipelining: pipelining,
    handler: handler,
    maxFrameSize: MAX_FRAME_SIZE,
    maxConn: maxConn
  )

proc close*(agent: SpoeAgent) {.async.} =
  if not agent.done.finished():
    agent.done.complete()

proc handleConn(agent: SpoeAgent, transport: StreamTransport, done: Future[void]) {.async.} =
  # Handle a single remote connection
  info "Incoming connection from ", id=agent.nextClientId, remoteAddr=transport.remoteAddress()
  var client = clientPool.grab()
  if client == nil:
    client = SpoeClient.new(agent, transport)
  else:
    client.init(transport)
  try:
    await client.handleConnection()
  except CancelledError:
    raiseAssert "No cancellations in this example"
  except TransportError as exc:
    error "Connection problem! ", msg=exc.msg
  except Exception:
    error "Error handling connection", msg=getCurrentExceptionMsg()
  finally:
    # Connections must always be closed to avoid resource leaks
    await transport.closeWait()
    clientPool.add(client)

proc run*(agent: SpoeAgent) {.async: (raises: [Exception]).} =
  let server = createStreamServer(initTAddress(agent.address), flags = {ReuseAddr})

  info "Accepting connections on ", localAddr=server.local
  agent.done = Future[void].init()
  try:
    while true:
      let accept = server.accept()
      discard await race(accept, agent.done)
      if agent.done.finished(): break
      asyncSpawn agent.handleConn(accept.read(), agent.done)
  finally:
    await server.closeWait()
    clientPool.close()
