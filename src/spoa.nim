from chronos import waitFor
import spoa/[agent, action, common, kv, request, typeddata]

export common, agent, request, kv, request, typeddata, SpoeActionScope, waitFor


when isMainModule:
  proc handler(req: SpoeRequest) {.gcsafe.} =
    echo "Handle request streamId=", req.streamId, " frameId=", req.frameId

    let message = req.getMessage("spoe-req")
    if message != nil:
      echo "Input args:"
      for key in message.keys:
        echo "\tkey: ", key, "\tvalue:", message.getArg(key)
      req.setVar(ScopeTransaction, "action", "redirect")
      req.setVar(ScopeTransaction, "data", "/hello-world")

  let address = "0.0.0.0:12345"
  waitFor SpoeAgent.new(handler, address).run()