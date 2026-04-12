#!/bin/sh
set -eu

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <requests_dir> <results_dir> [--once]" >&2
  exit 1
fi

REQUESTS_DIR="$1"
RESULTS_DIR="$2"
ONCE="false"

if [ "${3:-}" = "--once" ]; then
  ONCE="true"
fi

mkdir -p "$REQUESTS_DIR" "$RESULTS_DIR"

process_request() {
  req="$1"
  id=""
  source=""
  destination=""

  while IFS='=' read -r key value; do
    case "$key" in
      id) id="$value" ;;
      source) source="$value" ;;
      destination) destination="$value" ;;
    esac
  done < "$req"

  if [ -z "$id" ] || [ -z "$source" ] || [ -z "$destination" ]; then
    echo "status=error" > "$RESULTS_DIR/$(basename "$req")"
    echo "message=invalid request" >> "$RESULTS_DIR/$(basename "$req")"
    return
  fi

  mkdir -p "$(dirname "$destination")"
  if cp -a "$source" "$destination" 2>/tmp/root-copy-helper.err; then
    echo "status=ok" > "$RESULTS_DIR/$id.txt"
    echo "message=ok" >> "$RESULTS_DIR/$id.txt"
  else
    msg="$(cat /tmp/root-copy-helper.err 2>/dev/null | tr '\n' ' ')"
    echo "status=error" > "$RESULTS_DIR/$id.txt"
    echo "message=$msg" >> "$RESULTS_DIR/$id.txt"
  fi
  rm -f "$req"
}

while true; do
  for req in "$REQUESTS_DIR"/*.txt; do
    [ -e "$req" ] || continue
    process_request "$req"
    if [ "$ONCE" = "true" ]; then
      exit 0
    fi
  done
  if [ "$ONCE" = "true" ]; then
    exit 0
  fi
  sleep 1
done
