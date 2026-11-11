"""Disposable loopback HTTP fixture for real Chrome funnel queue/redirect tests."""
import json
import os
import sys
from pathlib import Path
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
state = {"bodies": [], "sinkHits": 0, "thirdPartyHits": 0, "unexpectedPathHits": 0, "retry": 0}
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Authorization,Content-Type")
    def send(self, status, body, location=None):
        payload=json.dumps(body).encode()
        self.send_response(status); self.cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        if location: self.send_header("Location", location)
        self.end_headers(); self.wfile.write(payload)
    def do_OPTIONS(self):
        self.send_response(204); self.cors(); self.end_headers()
    def do_GET(self):
        if self.path == "/stats": self.send(200,state)
        else:
            state["sinkHits"] += 1
            if self.server.third_party: state["thirdPartyHits"] += 1
            self.send(200,{})
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers.get("Content-Length",0))) or b"{}")
        if self.server.third_party:
            state["thirdPartyHits"] += 1; self.send(200,{}); return
        if self.path != "/api/client/workflow-events":
            state["unexpectedPathHits"] += 1; self.send(200,{}); return
        token=self.headers.get("Authorization")
        if token == "Bearer fixture-302": self.send(302,{},"/sink"); return
        if token == "Bearer fixture-307": self.send(307,{},f"http://127.0.0.1:{secondary.server_port}/sink"); return
        state["bodies"].append(body)
        if token == "Bearer fixture-retry":
            state["retry"] += 1
            if state["retry"] == 1: self.send(503,{"error":"retry"}); return
        self.send(200,{"acceptedIds":[e["id"] for e in body["events"]]})
primary=ThreadingHTTPServer(("127.0.0.1",0),Handler)
secondary=ThreadingHTTPServer(("127.0.0.1",0),Handler)
primary.third_party=False;secondary.third_party=True
for server in (primary,secondary):threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    environment=os.environ.copy()
    if sys.platform=='darwin': environment['CHROME_EXECUTABLE']=str(Path(__file__).with_name('workflow_chrome_launcher.py').resolve())
    result=subprocess.run(["flutter","test","--no-pub","--platform","chrome",
      f"--dart-define=WORKFLOW_TEST_ORIGIN=http://127.0.0.1:{primary.server_port}",
      f"--dart-define=API_BASE_URL=http://127.0.0.1:{primary.server_port}/api",
      "test/core/services/workflow_event_browser_test.dart"],env=environment)
    print(json.dumps({"workflow_fixture":{"sinkHits":state["sinkHits"],"thirdPartyHits":state["thirdPartyHits"],"requests":len(state["bodies"])},"exit_code":result.returncode}))
    raise SystemExit(result.returncode)
finally:
    for server in (primary,secondary):server.shutdown();server.server_close()
