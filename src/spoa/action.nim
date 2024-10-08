import kv
type
  SpoeActionKind* = enum
    SET_VAR = 1
    UNSET_VAR

  SpoeAction* = object
    kind*: SpoeActionKind
    list*: seq[SpoeKV]