import std/locks
import chronicles

type
  Pool*[T] = object
    L: Lock
    entries {.guard: L.}: seq[T]

proc new*[T](ctype: typedesc[Pool[T]]): ptr Pool[T] =
  debug "Pool: creating object pool"
  result = cast[ptr Pool[T]](alloc0(sizeof(Pool[T])))
  initLock(result.L)

proc add*[T](pool: ptr Pool[T], t: T) =
  withLock pool.L:
    pool.entries.add(t)
    debug "Add object to pool", size=pool.entries.len

proc grab*[T](pool: ptr Pool[T]): T =
  withLock pool.L:
    if pool.entries.len == 0:
      debug "Pool is empty"
      return nil
    result = pool.entries.pop()
    debug "Grab object from pool", size=pool.entries.len

proc close*[T](pool: ptr Pool[T]) =
  debug "Close pool"
  withLock pool.L:
    for client in pool.entries:
      client.close()
  deinitLock(pool.L)
  dealloc(pool)
