import std/tables
import action, message, typeddata

type
  SpoeRequest* = ref object
    streamId*: uint64
    frameId*: uint64
    messages*: seq[SpoeMessage]
    actions*: seq[SpoeAction]

proc new*(ctype: typedesc[SpoeRequest], streamId, frameId: uint64): SpoeRequest =
  result = SpoeRequest(streamId: streamId, frameId: frameId)

proc getMessage*(req: SpoeRequest, name: string): SpoeMessage =
  for message in req.messages:
    if message.name == name:
      result = message
      break

proc setVar*(req: SpoeRequest, scope: SpoeActionScope, name: string, value: auto) =
  let action = SpoeAction(
    kind: SET_VAR,
    scope: scope,
    name: name,
    value: toTypedData(value)
  )
  req.actions.add(action)

proc unsetVar*(req: SpoeRequest, scope: SpoeActionScope, name: string) =
  let action = SpoeAction(
    kind: UNSET_VAR,
    scope: scope,
    name: name
  )
  req.actions.add(action)