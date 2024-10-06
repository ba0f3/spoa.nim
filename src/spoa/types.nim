import std/posix

const
  MAX_FRAME_SIZE* = 16384
  SPOP_VERSION* = "2.0"
  SPOP_CAPABILITIES* = "pipelining"
  SPOE_FRAME_FLAG_FIN* = 0x00000001
  SPOE_FRAME_FLAG_ABORT* = 0x00000002

type
  SpoeDataKind* = enum
    NULL
    BOOLEAN
    INT32
    UINT32
    INT64
    UINT64
    IPV4
    IPV6
    STRING
    BINARY

  SpoeActionKind* = enum
    SET_VAR = 1
    UNSET_VAR

  SpoeFrameKind* = enum
    UNSET
    HAPROXY_HELLO
    HAPROXY_DISCONNECT
    NOTIFY
    AGENT_HELLO = 101
    AGENT_DISCONNECT
    ACK

  SpoeFrameError* = enum
    ERROR_NONE = 0
    ERROR_IO
    ERROR_TOUT
    ERROR_TOO_BIG
    ERROR_INVALID
    ERROR_NO_VSN
    ERROR_NO_FRAME_SIZE
    ERROR_NO_CAP
    ERROR_BAD_VSN
    ERROR_BAD_FRAME_SIZE
    ERROR_FRAG_NOT_SUPPORTED
    ERROR_INTERLACED_FRAMES
    ERROR_FRAMEID_NOTFOUND
    ERROR_RES
    ERROR_UNKNOWN = 99

  SpoeTypedData* = object
    case kind*: SpoeDataKind
    of BOOLEAN: b*: bool
    of INT32: i32*: int32
    of UINT32: u32*: uint32
    of INT64: i64*: int64
    of UINT64: u64*: uint64
    of IPV4: v4*: InAddr
    of IPV6: v6*: In6Addr
    of STRING, BINARY:
      s*: string
    else: discard

  SpoeFrameHeader* = object
    kind*: SpoeFrameKind
    flags*: uint32
    streamId*: uint64
    frameId*: uint64

  SpoeKV* = object
    key*: string
    value*: SpoeTypedData

  SpoeMessage* = object
    name*: string
    list*: seq[SpoeKV]

  SpoeAction* = object
    kind*: SpoeActionKind
    list*: seq[SpoeKV]

  SpoeFrame* = ref object
    kind*: SpoeFrameKind
    flags*: uint32
    #maxFrameSize*: uint64
    streamId*: uint64
    frameId*: uint64
    messages*: seq[SpoeMessage]
    actions*: seq[SpoeAction]
    list*: seq[SpoeKV]

  SpoeAgent* = ref object
    engineId*: string
    maxFrameSize*: uint64
    healthcheck*: bool
    pipelining*: bool