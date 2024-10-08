import ba0f3/[logger]
from chronos import waitFor
import spoa/[agent, action, request]

export agent, request, SpoeActionScope

proc handler(req: SpoeRequest) {.gcsafe.} =
  info "handle request", streamId=req.streamId, frameId=req.frameId

  let message = req.getMessage("spoe-req")
  if message != nil:
    echo message[]
  req.setVar(ScopeTransaction, "action", "redirect")
  req.setVar(ScopeTransaction, "data", "/hello-world")

when isMainModule:
  initLogger(level=lvlInfo)
  waitFor SpoeAgent.new(handler, "0.0.0.0:12345").run()