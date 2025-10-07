import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpExchange;

import java.io.*;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.regex.*;
import java.text.SimpleDateFormat;

public class Service {

    // Message model.
    static class Message {
        int id;
        String author;
        String content;
        long created;
        long updated;

        Message(int id, String author, String content) {
            long now = System.currentTimeMillis() * 1_000_000L;
            this.id = id;
            this.author = author;
            this.content = content;
            this.created = now;
            this.updated = now;
        }

        Map<String,Object> toMap() {
            Map<String,Object> map = new LinkedHashMap<>();
            map.put("id", id);
            map.put("author", author);
            map.put("content", content);
            map.put("created", created);
            map.put("updated", updated);
            return map;
        }
    }

    // Thread-safe Store.
    static class Store {
        private final ConcurrentHashMap<Integer, Message> data = new ConcurrentHashMap<>();
        private final AtomicInteger nextId = new AtomicInteger(0);

        public Message create(String author, String content) {
            int id = nextId.getAndIncrement();
            Message m = new Message(id, author, content);
            data.put(id, m);
            return m;
        }

        public Message get(int id) { return data.get(id); }

        public boolean delete(int id) { return data.remove(id) != null; }

        public Message put(int id, String author, String content) {
            Message m = data.get(id);
            if (m == null) return null;
            m.author = author;
            m.content = content;
            m.updated = System.currentTimeMillis() * 1_000_000L;
            return m;
        }

        public Message patch(int id, String author, String content) {
            Message m = data.get(id);
            if (m == null) return null;
            if (author != null) m.author = author;
            if (content != null) m.content = content;
            m.updated = System.currentTimeMillis() * 1_000_000L;
            return m;
        }

        public List<Message> list(int start, int limit) {
            List<Message> msgs = new ArrayList<>(data.values());
            msgs.sort(Comparator.comparingInt(a -> a.id));
            List<Message> result = new ArrayList<>();
            int count = 0;
            for (Message m : msgs) {
                if (m.id >= start && count < limit) {
                    result.add(m);
                    count++;
                }
            }
            return result;
        }

        public Integer previousId(int currentId) {
            return data.keySet().stream().filter(id -> id < currentId).max(Integer::compare).orElse(null);
        }

        public Integer nextId(int currentId) {
            return data.keySet().stream().filter(id -> id > currentId).min(Integer::compare).orElse(null);
        }
    }

    // JSON utility functions.
    static String toJson(Object obj) {
        if (obj instanceof Map<?,?>) {
            StringBuilder sb = new StringBuilder("{");
            boolean first = true;
            for (Map.Entry<?,?> e : ((Map<?,?>) obj).entrySet()) {
                if (!first) sb.append(",");
                sb.append("\"").append(e.getKey()).append("\":").append(toJson(e.getValue()));
                first = false;
            }
            sb.append("}");
            return sb.toString();
        } else if (obj instanceof List<?>) {
            StringBuilder sb = new StringBuilder("[");
            boolean first = true;
            for (Object item : (List<?>) obj) {
                if (!first) sb.append(",");
                sb.append(toJson(item));
                first = false;
            }
            sb.append("]");
            return sb.toString();
        } else if (obj instanceof String) {
            return "\"" + ((String)obj).replace("\"","\\\"") + "\"";
        } else if (obj instanceof Number || obj instanceof Boolean) {
            return obj.toString();
        } else {
            return "\"\"";
        }
    }

    static Map<String,Object> parseJson(InputStream is) throws IOException {
        String s = new String(is.readAllBytes(), StandardCharsets.UTF_8);
        s = s.trim();
        if (!s.startsWith("{") || !s.endsWith("}")) return null;
        Map<String,Object> map = new HashMap<>();
        Pattern p = Pattern.compile("\"(\\w+)\"\\s*:\\s*\"([^\"]*)\"");
        Matcher m = p.matcher(s);
        while (m.find()) {
            map.put(m.group(1), m.group(2));
        }
        return map;
    }

    // Query parsing utility function.
    static Map<String,String> parseQuery(String query) {
        Map<String,String> map = new HashMap<>();
        if (query == null || query.isEmpty()) return map;
        for (String pair : query.split("&")) {
            String[] kv = pair.split("=",2);
            if (kv.length==2) map.put(kv[0], kv[1]);
        }
        return map;
    }

    // Standard response sender.
    static void sendResponse(HttpExchange exchange, int code, Map<String,Object> body, Map<String,String> headers) throws IOException {
        if (headers != null) {
            for (Map.Entry<String,String> e : headers.entrySet()) exchange.getResponseHeaders().add(e.getKey(), e.getValue());
        }
        String json = body != null ? toJson(body) : "";
        byte[] bytes = json.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type","application/json");
        exchange.sendResponseHeaders(code, bytes.length);
        OutputStream os = exchange.getResponseBody();
        os.write(bytes);
        os.close();
    }

    // Router and router creation function.
    @FunctionalInterface
    interface Handler {
        void handle(Store store, String method, int version,
                    Map<String,String> params,
                    Map<String,String> query,
                    Map<String,Object> body,
                    HttpExchange exchange,
                    Map<String,String> headers) throws IOException;
    }

    static Map<Integer, Map<String, Map<Pattern, Handler>>> createRouter(Store store) {
        Map<Integer, Map<String, Map<Pattern, Handler>>> router = new HashMap<>();

        // Initialize maps
        for (int v = 0; v <= 2; v++) {
            router.put(v, new HashMap<>());
            for (String method : List.of("GET","POST","PUT","PATCH","DELETE")) {
                router.get(v).put(method, new LinkedHashMap<>());
            }
        }

        // Version 0: all 410 Gone
        for (String method : List.of("GET","POST","PUT","PATCH","DELETE")) {
            router.get(0).get(method).put(Pattern.compile(".*"), (s,m,v,params,query,body,ex,headers)->{
                ex.sendResponseHeaders(410, -1);
                ex.close();
            });
        }

        // Version 1 & 2 handlers
        for (int version : List.of(1,2)) {
            router.get(version).get("GET").put(Pattern.compile("/?"), (s,m,v,params,query,body,ex,headers)->{
                sendResponse(ex, 200, Map.of("status","OK"), headers);
            });

            router.get(version).get("POST").put(Pattern.compile("/message/?"), (s,m,v,params,query,body,ex,headers)->{
                Message msg = s.create((String)body.get("author"), (String)body.get("content"));
                sendResponse(ex, 201, msg.toMap(), headers);
            });

            router.get(version).get("GET").put(Pattern.compile("/message/?"), (s,m,v,params,query,body,ex,headers)->{
                int start = query.containsKey("start") ? Integer.parseInt(query.get("start")) : 0;
                List<Message> msgs = s.list(start, 10);
                Map<String,Object> resp = new HashMap<>();
                resp.put("data", msgs.stream().map(Message::toMap).toList());
                resp.put("previous", msgs.isEmpty()?null:s.previousId(msgs.get(0).id));
                resp.put("next", msgs.size()<10?null:s.nextId(msgs.get(msgs.size()-1).id));
                sendResponse(ex, 200, resp, headers);
            });

            router.get(version).get("GET").put(Pattern.compile("/message/(\\d+)/?"), (s,m,v,params,query,body,ex,headers)->{
                int id = Integer.parseInt(params.get("id"));
                Message msg = s.get(id);
                if (msg == null) sendResponse(ex, 404, Map.of("error","Not found"), headers);
                else sendResponse(ex, 200, msg.toMap(), headers);
            });

            router.get(version).get("PUT").put(Pattern.compile("/message/(\\d+)/?"), (s,m,v,params,query,body,ex,headers)->{
                int id = Integer.parseInt(params.get("id"));
                Message msg = s.put(id,(String)body.get("author"),(String)body.get("content"));
                if (msg == null) sendResponse(ex, 404, Map.of("error","Not found"), headers);
                else sendResponse(ex, 200, msg.toMap(), headers);
            });

            router.get(version).get("PATCH").put(Pattern.compile("/message/(\\d+)/?"), (s,m,v,params,query,body,ex,headers)->{
                int id = Integer.parseInt(params.get("id"));
                String author = body.get("author") != null ? (String)body.get("author") : null;
                String content = body.get("content") != null ? (String)body.get("content") : null;
                Message msg = s.patch(id, author, content);
                if (msg == null) sendResponse(ex, 404, Map.of("error","Not found"), headers);
                else sendResponse(ex, 200, msg.toMap(), headers);
            });

            router.get(version).get("DELETE").put(Pattern.compile("/message/(\\d+)/?"), (s,m,v,params,query,body,ex,headers)->{
                int id = Integer.parseInt(params.get("id"));
                boolean ok = s.delete(id);
                if (!ok) sendResponse(ex, 404, Map.of("error","Not found"), headers);
                else sendResponse(ex, 200, null, headers);
            });
        }

        return router;
    }

    // Main server.
    public static void main(String[] args) throws IOException {
        int port = 8000;
        String host = "127.0.0.1";
        Store store = new Store();
        Map<Integer, Map<String, Map<Pattern, Handler>>> router = createRouter(store);

        // Deprecation map
        Map<Integer, Long[]> deprecation = new HashMap<>();
        deprecation.put(1, new Long[]{System.currentTimeMillis()/1000, System.currentTimeMillis()/1000 + 30*24*3600}); // deprecated
        deprecation.put(0, new Long[]{System.currentTimeMillis()/1000 - 3600, System.currentTimeMillis()/1000}); // removed

        HttpServer server = HttpServer.create(new InetSocketAddress(host, port), 0);
        server.createContext("/", (exchange)->{
            try {
                String versionHeader = exchange.getRequestHeaders().getFirst("Accept");
                int version = -1;
                if (versionHeader != null) {
                    Matcher m = Pattern.compile("version\\s*=\\s*(\\d+)").matcher(versionHeader);
                    if (m.find()) version = Integer.parseInt(m.group(1));
                }

                if (version == -1) {
                    sendResponse(exchange, 406, Map.of("error","Version not specified"), null);
                    return;
                }

                if (!router.containsKey(version)) {
                    sendResponse(exchange, 406, Map.of("error","Invalid version"), null);
                    return;
                }

                String path = exchange.getRequestURI().getPath();
                String method = exchange.getRequestMethod();
                Map<String,String> query = parseQuery(exchange.getRequestURI().getQuery());
                Map<String,Object> body = null;
                if ("POST".equals(method) || "PUT".equals(method) || "PATCH".equals(method)) {
                    body = parseJson(exchange.getRequestBody());
                }

                Map<Pattern, Handler> methodMap = router.get(version).get(method);
                if (methodMap == null) {
                    sendResponse(exchange, 405, Map.of("error","Method not allowed"), null);
                    return;
                }

                Handler matchedHandler = null;
                Map<String,String> pathParams = new HashMap<>();
                for (Map.Entry<Pattern, Handler> entry : methodMap.entrySet()) {
                    Matcher matcher = entry.getKey().matcher(path);
                    if (matcher.matches()) {
                        matchedHandler = entry.getValue();
                        if (matcher.groupCount() >= 1) pathParams.put("id", matcher.group(1));
                        break;
                    }
                }

                if (matchedHandler != null) {
                    // Add deprecation headers if applicable
                    Map<String,String> headers = new HashMap<>();
                    if (deprecation.containsKey(version)) {
                        headers.put("Deprecation", "@" + deprecation.get(version)[0]);
                        SimpleDateFormat df = new SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss z", Locale.US);
                        headers.put("Sunset", df.format(new Date(deprecation.get(version)[1]*1000)));
                    }
                    matchedHandler.handle(store, method, version, pathParams, query, body, exchange, headers);
                } else {
                    sendResponse(exchange, 404, Map.of("error","Resource not found"), null);
                }

            } catch(Exception e) {
                e.printStackTrace();
                sendResponse(exchange, 500, Map.of("error","Internal error"), null);
            }
        });

        server.setExecutor(Executors.newCachedThreadPool());
        server.start();
        System.out.println("Server running at http://127.0.0.1:8000/");
    }
}
