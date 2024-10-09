import std/streams
import ./[typeddata, utils]

const
  NB_ARGS_SET = 3
  NB_ARGS_UNSET = 2

type
  SpoeActionKind* = enum
    SET_VAR = 1
    UNSET_VAR

  SpoeActionScope* = enum
    ScopeProcess
    ScopeSession
    ScopeTransaction
    ScopeRequest
    ScopeResponse

  SpoeAction* = object
    kind*: SpoeActionKind
    scope*: SpoeActionScope
    name*: string
    value*: SpoeTypedData

proc writeAction*(stream: StringStream, action: SpoeAction) =
  var nbArg = if action.kind == SET_VAR: NB_ARGS_SET else: NB_ARGS_UNSET
  stream.writeData(addr action.kind, sizeof(SpoeActionKind))
  stream.writeData(addr nbArg, 1)
  stream.writeData(addr action.scope, sizeof(SpoeActionScope))
  stream.writeString(action.name)
  if action.kind == SET_VAR:
    stream.writeTypedData(action.value)