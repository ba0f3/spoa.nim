import std/tables
import ./[action, kv, message, typeddata]

type
  Message* = ref object
    args: TableRef[string, SpoeTypedData]

  SpoeRequest* = ref object
    streamId*: uint64
    frameId*: uint64
    messages: Table[string, Message]
    actions*: seq[SpoeAction]

proc new*(ctype: typedesc[SpoeRequest], streamId, frameId: uint64): SpoeRequest =
  result = SpoeRequest(streamId: streamId, frameId: frameId)

  result.messages = initTable[string, Message](2)

proc addMessage*(req: SpoeRequest, name: string, data: seq[SpoeKV]) =
  req.messages[name] = Message(
    args: newTable[string, SpoeTypedData](10)
  )
  for kv in data:
    req.messages[name].args[kv.key] = kv.value

proc addMessage*(req: SpoeRequest, message: SpoeMessage) {.inline.} =
  req.addMessage(message.name, message.list)

proc getMessage*(req: SpoeRequest, name: string): Message =
  req.messages.getOrDefault(name, nil)


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

iterator keys*(message: Message): string =
    for key in message.args.keys:
      yield key

proc getArg*(message: Message, key: string): SpoeTypedData =
  message.args.getOrDefault(key, toTypedData(nil))