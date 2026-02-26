import os
import socketserver
from http.server import SimpleHTTPRequestHandler
from pathlib import Path


def main() -> None:
    base_dir = Path(__file__).resolve().parent
    website_dir = base_dir / "website"
    if not website_dir.exists():
        raise SystemExit("Missing ./website directory")

    os.chdir(website_dir)

    port_str = os.environ.get("PORT", "8080")
    try:
        port = int(port_str)
    except ValueError as exc:
        raise SystemExit(f"Invalid PORT: {port_str!r}") from exc

    handler = SimpleHTTPRequestHandler

    with socketserver.ThreadingTCPServer(("0.0.0.0", port), handler) as httpd:
        httpd.allow_reuse_address = True
        print(f"Serving {website_dir} on http://0.0.0.0:{port}")
        httpd.serve_forever()


if __name__ == "__main__":
    main()