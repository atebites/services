import argparse, json, os, re, sys, time
from http import HTTPStatus, HTTPMethod
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs
from typing import Any, Callable, Dict, List, Optional, Tuple
from contextlib import suppress
from dataclasses import dataclass, asdict
from collections import defaultdict
from email.utils import formatdate
from functools import partial
from threading import Lock

@dataclass
class Message:
    id: int
    author: str
    content: str
    created: int
    updated: int

    @staticmethod
    def now_ns() -> int:
        return time.time_ns()
    
    @classmethod
    def create(cls, id: int, author: str, content: str) -> "Message":
        now = cls.now_ns()
        return cls(id=id, author=author, content=content, created=now, updated=now)
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


class Store:
    def __init__(self):
        self._lock = Lock()
        self._next_id = 0
        self._data: Dict[int, Message] = {}

    def create(self, author: str, content: str) -> Message:
        with self._lock:
            id = self._next_id
            self._next_id += 1
            message = Message.create(id, author, content)
            self._data[id] = message
            return message

    def get(self, id: int) -> Optional[Message]:
        return self._data.get(id)

    def list(self, start, limit) -> Tuple[List[Message], Message, List[Message]]:
        if len(self._data) == 0: return ([],None,[])
        data = sorted(self._data.values(), key = lambda message: message.id, reverse=False)
        index = 0
        for index, value in  enumerate(data):
            if value.id >= start:
                break
        else:
            return ([],None,[])
        before = data[max(0, index - limit):index]
        current = data[index]
        after = data[index + 1:min(len(data), index + 11)]
        return (before, current, after)

    def put(self, id: int, author: str, content: str) -> Optional[Message]:
        with self._lock:
            message = self._data.get(id)
            if not message: return None
            message.author = author
            message.content = content
            message.updated = Message.now_ns()
            return message

    def patch(self, id: int, author = None, content = None) -> Optional[Message]:
        with self._lock:
            message = self._data.get(id)
            if not message: return None
            if author is not None: message.author = author
            if content is not None: message.content = content
            message.updated = Message.now_ns()
            return message

    def delete(self, id: int) -> bool:
        with self._lock:
            return self._data.pop(id, None) is not None


class MessageHandlers:
    @staticmethod
    def create(store, method, version, params, query, body) -> Tuple[HTTPStatus, Optional[Dict[str, Any]], Optional[Dict[str, str]]]:
        # TODO: Validate input.
        return (HTTPStatus.CREATED, store.create(body.get("author"), body.get("content")).to_dict())

    @staticmethod
    def get(store, method, version, params, query, body) -> Tuple[HTTPStatus, Optional[Dict[str, Any]], Optional[Dict[str, str]]]:
        # TODO: Validate input.
        message = store.get(int(params["id"]))
        if not message: return (HTTPStatus.NOT_FOUND, {"error": "Message with provided id not found."})
        return (HTTPStatus.OK, message.to_dict())

    @staticmethod
    def list(store, method, version, params, query, body) -> Tuple[HTTPStatus, Optional[Dict[str, Any]], Optional[Dict[str, str]]]:
        # TODO: Validate input.
        start = int(query["start"][0]) if "start" in query else 0
        limit = 10
        before, current, after = store.list(start, limit)
        if current is None: return (HTTPStatus.OK, {"data": [], "next": None, "previous": (before[0].id if len(before) > 0 else None)})
        data = [current.to_dict()] + ([message.to_dict() for message in after[0:limit-1]] if len(after) > 0 else [])
        return (HTTPStatus.OK, {
            "data": data,
            "next": (after[limit-1].id if len(after) == limit else None),
            "previous": (before[0].id if len(before) > 0 else None)
        })
    
    @staticmethod
    def put(store, method, version, params, query, body) -> Tuple[HTTPStatus, Optional[Dict[str, Any]], Optional[Dict[str, str]]]:
        # TODO: Validate input.
        message = store.put(int(params["id"]), body.get("author"), body.get("content"))
        if not message: return (HTTPStatus.NOT_FOUND, {"error":"Message with provided id not found"})
        return (HTTPStatus.OK, message.to_dict())

    @staticmethod
    def patch(store, method, version, params, query, body) -> Tuple[HTTPStatus, Optional[Dict[str, Any]], Optional[Dict[str, str]]]:
        # TODO: Validate input.
        message = store.patch(int(params["id"]), body.get("author"), body.get("content"))
        if not message: return (HTTPStatus.NOT_FOUND, {"error":"Message with provided id not found"})
        return (HTTPStatus.OK, message.to_dict())

    @staticmethod
    def delete(store, method, version, params, query, body) -> Tuple[HTTPStatus, Optional[Dict[str, Any]], Optional[Dict[str, str]]]:
        # TODO: Validate input.
        if not store.delete(int(params["id"])): return (HTTPStatus.NOT_FOUND, {"error":"Message with provided id not found"})
        return (HTTPStatus.OK,)


class RequestHandler(BaseHTTPRequestHandler):
    def __init__(self, router, deprecation, store, *args, **kwargs):
        self.router: Dict[int, Dict[HTTPMethod, Dict[str, Callable[
            [Store, int, HTTPMethod, Dict[str, str], Dict[str, str], Optional[Dict[str, Any]]],
            Tuple[HTTPStatus, Optional[Dict[str, Any]], Optional[Dict[str, str]]]
        ]]]] = router
        self.deprecation: Dict[int, Tuple[int, int]] = deprecation
        self.store: Store = store
        super().__init__(*args, **kwargs)

    def handle_one_request(self):
        try:
            # Get the request data.
            self.raw_requestline = self.rfile.readline(65537)
            if len(self.raw_requestline) > 65536:
                self.requestline = ''
                self.request_version = ''
                self.command = ''
                self._respond(HTTPStatus.REQUEST_URI_TOO_LONG, None, {"error": "Request URI too long."})
                return
            if not self.raw_requestline:
                self.close_connection = True
                return
            if not self.parse_request():
                return
            request_content_length = 0
            with suppress(Exception): request_content_length = int(self.headers.get('Content-Length', 0))
            request_body = None
            if request_content_length > 0:
                with suppress(json.JSONDecodeError): request_body = json.loads(self.rfile.read(request_content_length).decode('utf-8'))
                if request_body is None:
                    self._respond(HTTPStatus.BAD_REQUEST, None, {"error": "Malformed JSON body."})
                    return
            
            # Extract the version.
            request_version = None
            with suppress(Exception): request_version = int(re.search(r"(?:^|[,;])\s*version\s*=\s*([^,; ]+)\s*", self.headers.get("Accept")).group(1).strip())
            if request_version is None or request_version not in self.router:
                self._respond(HTTPStatus.NOT_ACCEPTABLE, None, {"error": "Invalid or missing version."})
                return
            
            # Confirm that the method is allowed.
            request_method = HTTPMethod(self.command)
            if request_method not in self.router[request_version]:
                self._respond(HTTPStatus.METHOD_NOT_ALLOWED, None, {"error": "Method not allowed."})
                return
            
            # Extracting the path and query.
            request_split = urlsplit(self.path)
            request_path = request_split.path
            request_query = parse_qs(request_split.query)
            
            # Confirm that the path exists.
            request_paths = self.router[request_version][request_method]
            for request_path_regex, request_handler in request_paths.items():
                match = re.fullmatch(request_path_regex, request_path)
                if match:
                    request_params = match.groupdict()
                    break
            else:
                self._respond(HTTPStatus.NOT_FOUND, request_version, {"error": "Resource not found."})
                return
            
            # Execute the handler.
            response_status, response_body, response_headers = (list(request_handler(self.store, request_method, request_version, request_params, request_query, request_body)) + [None]*2)[:3]
            if request_version in self.deprecation:
                if response_headers is None:
                    response_headers = {}
                response_headers["Deprecation"] = f"@{self.deprecation[request_version][0]}"
                response_headers["Sunset"] = formatdate(timeval=self.deprecation[request_version][1], usegmt=True)
            self._respond(response_status, request_version, response_body, response_headers)  
        except Exception as e:
            self._respond(HTTPStatus.INTERNAL_SERVER_ERROR, None, {"error": "Internal error."})

    def _respond(self, status: HTTPStatus, version: Optional[int] = None, body: Any = None, headers: Optional[Dict[str,str]] = None):
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json" + (f"; version={version}" if version is not None else ""))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        if headers is not None:
            for key, value in headers.items():
                self.send_header(key, value)
        self.end_headers()
        if body is not None:
            self.wfile.write(json.dumps(body).encode("utf-8"))
        self.wfile.flush()
        self.close_connection = True


def main(arguments):
    # Validate arguments.
    if "address" not in arguments or not arguments.address:
        arguments.address = "127.0.0.1"
    if "port" not in arguments or not arguments.port:
        arguments.port = 8000
    
    # Router maps a METHOD request to a RESOURCE with a VERSION to a HANDLER.
    # - VERSION is extracted from the request headers.
    # - METHOD is one of GET, POST, PUT, PATCH, DELETE.
    # - PATH and QUERY are extracted from the URL in the form: http://{API_HOST}:{API_PORT}/{PATH}?{QUERY}
    # - PARAMS is formed by regex matching a PATH to a HANDLER.
    # - HANDLER takes six arguments: STORE, METHOD, VERSION, PARAMS, QUERY, and BODY and returns a STATUS_CODE and optionally a BODY and some headers.
    # router[VERSION][METHOD][PATH_REGEX] = HANDLER
    
    router = defaultdict(lambda: defaultdict(dict))

    # Deprecation adds additional headers when a version is marked as deprecated.
    # deprecation[VERSION] = (DEPRECATION_TIME, SUNSET_TIME)

    deprecation = {}

    # Store simulates a database connection with functions to create, get, list, put, patch, and delete.

    store = Store()
        
    # Define handlers for the version 0 API, everything responds with "410 Gone".
    router[0][HTTPMethod.GET][r".*"] = lambda store, method, version, params, query, body: (HTTPStatus.GONE,)
    router[0][HTTPMethod.POST][r".*"] = lambda store, method, version, params, query, body: (HTTPStatus.GONE,)
    router[0][HTTPMethod.PUT][r".*"] = lambda store, method, version, params, query, body: (HTTPStatus.GONE,)
    router[0][HTTPMethod.PATCH][r".*"] = lambda store, method, version, params, query, body: (HTTPStatus.GONE,)
    router[0][HTTPMethod.DELETE][r".*"] = lambda store, method, version, params, query, body: (HTTPStatus.GONE,)

    # Define handlers for the version 1 API.
    router[1][HTTPMethod.GET][r"/?"] = lambda store, method, version, params, query, body: (HTTPStatus.OK, {"status": "OK"})
    router[1][HTTPMethod.POST][r"/message/?"] = MessageHandlers.create
    router[1][HTTPMethod.GET][r"/message/(?P<id>\d+)/?"] = MessageHandlers.get
    router[1][HTTPMethod.GET][r"/message/?"] = MessageHandlers.list
    router[1][HTTPMethod.PUT][r"/message/(?P<id>\d+)/?"] = MessageHandlers.put
    router[1][HTTPMethod.PATCH][r"/message/(?P<id>\d+)/?"] = MessageHandlers.patch
    router[1][HTTPMethod.DELETE][r"/message/(?P<id>\d+)/?"] = MessageHandlers.delete

    # Define handlers for the version 2 API.
    router[2][HTTPMethod.GET][r"/?"] = lambda store, method, version, params, query, body: (HTTPStatus.OK, {"status": "OK"})
    router[2][HTTPMethod.POST][r"/message/?"] = MessageHandlers.create
    router[2][HTTPMethod.GET][r"/message/(?P<id>\d+)/?"] = MessageHandlers.get
    router[2][HTTPMethod.GET][r"/message/?"] = MessageHandlers.list
    router[2][HTTPMethod.PUT][r"/message/(?P<id>\d+)/?"] = MessageHandlers.put
    router[2][HTTPMethod.PATCH][r"/message/(?P<id>\d+)/?"] = MessageHandlers.patch
    router[2][HTTPMethod.DELETE][r"/message/(?P<id>\d+)/?"] = MessageHandlers.delete

    # Mark versions 0 and 1 as deprecated.
    # Note: In a real service these values would be fixed when the API versions were deprecated/sunset.
    deprecation[0] = (int(time.time()) - 60*60*24*30, int(time.time()))
    deprecation[1] = (int(time.time()), int(time.time()) + 60*60*24*30)

    # Begin serving the API.
    handler = partial(RequestHandler, router, deprecation, store)
    server = ThreadingHTTPServer((arguments.address, arguments.port), handler)

    try:
        print(f"Serving on http://{arguments.address}:{arguments.port}/...")
        server.serve_forever()
    except KeyboardInterrupt:
        print("\r", end = "")
    finally:
        print("Shutting down...")
        with suppress(KeyboardInterrupt): server.shutdown()


def cli(args):
    parser = argparse.ArgumentParser(description="Python message service")
    parser.add_argument("-a", "--address", default=os.environ.get("API_ADDRESS", "127.0.0.1"), help="Bind address (default: $API_ADDRESS or 127.0.0.1)")
    parser.add_argument("-p", "--port", default=int(os.environ.get("API_PORT", "8000")), type=int, help="Bind port (default: $API_PORT or 8000)")
    return parser.parse_args(args)


if __name__ == "__main__":
    with suppress(KeyboardInterrupt): main(cli(sys.argv[1:]))
