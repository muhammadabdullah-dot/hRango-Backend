"""Delivers webhooks as a service of its own (set WEBHOOK_WORKER=false for the API then).

  .venv\\Scripts\\python.exe -m scripts.webhooks            keep running (poll every WEBHOOK_POLL_SECONDS)
  .venv\\Scripts\\python.exe -m scripts.webhooks --once     send what is due now and stop
"""
import argparse
import signal
import sys
import threading

from app.core.config import settings
from app.core.db import Db, connect
from app.core.logging import setup_logging
from app.services.webhook_dispatcher import dispatch_once, run_forever


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    setup_logging()
    p = argparse.ArgumentParser(description="Deliver HRango webhooks.")
    p.add_argument("--once", action="store_true")
    a = p.parse_args()
    if a.once:
        conn = connect()
        total = 0
        while n := dispatch_once(Db(conn)):
            total += n
        conn.close()
        print(f"{total} deliveries attempted")
        return
    stop = threading.Event()
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    print(f"delivering webhooks every {settings.webhook_poll_seconds}s; Ctrl+C to stop")
    run_forever(stop, settings.webhook_poll_seconds)


if __name__ == "__main__":
    main()
