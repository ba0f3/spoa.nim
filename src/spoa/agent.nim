import chronos
import ba0f3/logger

import common, client

export SpoeAgent

proc new*(ctype: typedesc[SpoeAgent], handler: SpoeHandler, address = "127.0.0.1:12345", pipelining = true): SpoeAgent =
  result = SpoeAgent(address: address, pipelining: pipelining, handler: handler)
  result.maxFrameSize = MAX_FRAME_SIZE

proc close*(agent: SpoeAgent) {.async.} =
  if not agent.done.finished():
    agent.done.complete()

proc handleConn(agent: SpoeAgent, transport: StreamTransport, done: Future[void]) {.async: (raises: [IOError, OSError, Exception]).} =

  # Handle a single remote connection
  try:
    debug "Incoming connection from ", remoteAddr=transport.remoteAddress()
    var client = SpoeClient.new(agent, transport)
    await client.handleConnection()

  except CancelledError:
    raiseAssert "No cancellations in this example"
  except TransportError as exc:
    error "Connection problem! ", msg=exc.msg
  finally:
    # Connections must always be closed to avoid resource leaks
    await transport.closeWait()


proc run*(agent: SpoeAgent) {.async: (raises: [Exception]).} =
  let server = createStreamServer(initTAddress(agent.address), flags = {ReuseAddr})

  debug "Accepting connections on ", localAddr=server.local
  agent.done = Future[void].init()
  try:
    while true:
      let accept = server.accept()
      discard await race(accept, agent.done)
      if agent.done.finished(): break
      asyncSpawn agent.handleConn(accept.read(), agent.done)
  finally:
    await server.closeWait()
