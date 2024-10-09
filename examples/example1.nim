import spoa

proc handler(req: SpoeRequest) {.gcsafe.} =
  #echo "Handle request streamId=", req.streamId, " frameId=", req.frameId

  let message = req.getMessage("spoe-req")
  if message != nil:
    let path = message.getArg("path").getStr()
    if path  == "/redirect":
      req.setVar(ScopeTransaction, "action", "redirect")
      req.setVar(ScopeTransaction, "data", "/hello-world")
    elif path == "/deny":
      req.setVar(ScopeTransaction, "action", "deny")
    elif path == "/drop":
      req.setVar(ScopeTransaction, "action", "drop")
    elif path == "/error":
      req.setVar(ScopeTransaction, "error", 1)

let address = "0.0.0.0:12345"
waitFor SpoeAgent.new(handler, address, pipelining = false).run()