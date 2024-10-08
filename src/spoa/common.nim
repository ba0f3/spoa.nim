import std/posix
import chronos

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

  SpoeAgent* = ref object
    address*: string
    maxFrameSize*: uint32
    pipelining*: bool
    done*: Future[void]