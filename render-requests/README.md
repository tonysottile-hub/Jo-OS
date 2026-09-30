# Render requests

Jo Core creates one JSON request per render. Committing a request triggers the free GitHub Actions FFmpeg worker. Each request points to a manifest and names the output MP4. A render artifact is evidence only; publishing remains gated by Jo Core QA.
