import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class Server {

    private static final int PORT = 3000;
    private static final Path ROOT = Path.of(".").toAbsolutePath().normalize();

    private static final Map<String, String> MIME_TYPES = Map.ofEntries(
            Map.entry(".html",  "text/html"),
            Map.entry(".js",    "application/javascript"),
            Map.entry(".mjs",   "application/javascript"),
            Map.entry(".css",   "text/css"),
            Map.entry(".json",  "application/json"),
            Map.entry(".png",   "image/png"),
            Map.entry(".jpg",   "image/jpeg"),
            Map.entry(".jpeg",  "image/jpeg"),
            Map.entry(".gif",   "image/gif"),
            Map.entry(".svg",   "image/svg+xml"),
            Map.entry(".ico",   "image/x-icon"),
            Map.entry(".woff",  "font/woff"),
            Map.entry(".woff2", "font/woff2"),
            Map.entry(".txt",   "text/plain")
    );

    public static void main(String[] args) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress(PORT), 0);
        server.createContext("/", Server::handle);
        server.start();
        System.out.println("서버 실행 중: http://localhost:" + PORT);
    }

    private static void handle(HttpExchange exchange) throws IOException {
        String raw = exchange.getRequestURI().getRawPath();
        String urlPath = URLDecoder.decode(raw, StandardCharsets.UTF_8);

        Path filePath = ROOT.resolve(urlPath.replaceFirst("^/+", "")).normalize();

        if (!filePath.startsWith(ROOT)) {
            send(exchange, 403, "text/plain", "Forbidden".getBytes());
            return;
        }

        if (!Files.exists(filePath)) {
            send(exchange, 404, "text/plain", "Not Found".getBytes());
            return;
        }

        if (Files.isDirectory(filePath)) {
            Path indexPath = filePath.resolve("index.html");
            if (Files.exists(indexPath)) {
                send(exchange, 200, "text/html", Files.readAllBytes(indexPath));
            } else {
                serveDirectory(exchange, filePath, urlPath);
            }
            return;
        }

        String name = filePath.getFileName().toString();
        int dot = name.lastIndexOf('.');
        String ext = dot >= 0 ? name.substring(dot) : "";
        String contentType = MIME_TYPES.getOrDefault(ext, "application/octet-stream");

        send(exchange, 200, contentType, Files.readAllBytes(filePath));
    }

    private static void serveDirectory(HttpExchange exchange, Path dirPath, String urlPath) throws IOException {
        List<String> rows = new ArrayList<>();
        try (DirectoryStream<Path> stream = Files.newDirectoryStream(dirPath)) {
            for (Path entry : stream) {
                boolean isDir = Files.isDirectory(entry);
                String name = entry.getFileName().toString();
                String href = urlPath.replaceAll("/+$", "") + "/" + name + (isDir ? "/" : "");
                rows.add("<li><a href=\"" + href + "\">" + name + (isDir ? "/" : "") + "</a></li>");
            }
        }
        String html = "<!DOCTYPE html><html><body><h2>" + urlPath + "</h2><ul>"
                + String.join("\n", rows) + "</ul></body></html>";
        send(exchange, 200, "text/html", html.getBytes(StandardCharsets.UTF_8));
    }

    private static void send(HttpExchange exchange, int status, String contentType, byte[] body) throws IOException {
        exchange.getResponseHeaders().set("Content-Type", contentType);
        exchange.sendResponseHeaders(status, body.length);
        try (OutputStream os = exchange.getResponseBody()) {
            os.write(body);
        }
    }
}
