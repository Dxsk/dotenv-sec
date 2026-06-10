#!/usr/bin/env python3
import http.server, datetime, sys, os

LOG = os.environ.get("OOB_LOG", "/data/hits.log")
PORT = int(os.environ.get("OOB_BIND_PORT", "8080"))


class H(http.server.BaseHTTPRequestHandler):
    def handle_one(self):
        ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
        n = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(n).decode("latin-1") if n else ""
        hdrs = "; ".join(f"{k}: {v}" for k, v in self.headers.items())
        line = f"[{ts}] {self.client_address[0]} {self.command} {self.path} | {hdrs} | {body}\n"
        sys.stdout.write(line)
        sys.stdout.flush()
        try:
            with open(LOG, "a") as f:
                f.write(line)
        except OSError:
            pass
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = do_OPTIONS = do_HEAD = handle_one

    def log_message(self, *a):
        pass


http.server.ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
