import time
from collections import defaultdict, deque


class SlidingWindowLimiter:
    """Per-key request limiter, kept in memory.

    Good enough for a single instance and for tests. Behind several instances
    use a shared store (for example Redis) or the gateway / WAF limiter; the
    OTP limits are additionally enforced from the database, so they hold
    across instances."""

    def __init__(self, limit: int, window_seconds: int = 60, clock=time.monotonic):
        self.limit = limit
        self.window = window_seconds
        self.clock = clock
        self._hits: dict[str, deque] = defaultdict(deque)

    def allow(self, key: str) -> bool:
        now = self.clock()
        q = self._hits[key]
        while q and now - q[0] > self.window:
            q.popleft()
        if len(q) >= self.limit:
            return False
        q.append(now)
        return True
