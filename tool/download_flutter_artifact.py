"""Resume a Flutter SDK artifact download if the default Windows downloader fails."""
import pathlib
import sys
import urllib.request

url, destination = sys.argv[1:]
path = pathlib.Path(destination)
path.parent.mkdir(parents=True, exist_ok=True)
for attempt in range(12):
    try:
        start = path.stat().st_size if path.exists() else 0
        request = urllib.request.Request(url, headers={"Range": f"bytes={start}-"})
        with urllib.request.urlopen(request, timeout=60) as response:
            with path.open("ab" if response.status == 206 else "wb") as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
        print(f"Downloaded {path.name}: {path.stat().st_size} bytes", flush=True)
        break
    except Exception as error:
        print(f"Retry {attempt}: {type(error).__name__}", flush=True)
else:
    raise SystemExit("Download failed")
