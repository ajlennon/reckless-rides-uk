#!/usr/bin/env bash
# Resolve Python interpreter with google-api-client installed (prefer 3.10).
resolve_youtube_python() {
  local py
  for py in "${YOUTUBE_PYTHON:-}" \
    "$(command -v python3.10 2>/dev/null || true)" \
    "$(command -v python3 2>/dev/null || true)"; do
    [[ -n "$py" && -x "$py" ]] || continue
    if "$py" -c "import google.auth" 2>/dev/null; then
      echo "$py"
      return 0
    fi
  done
  echo "No Python with google-auth found. Run: python3.10 -m pip install --user -r requirements-youtube.txt" >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  resolve_youtube_python
fi
