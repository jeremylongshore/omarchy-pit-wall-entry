#!/bin/sh
# A screenshot is invalid until each production API path populated the panel.
set -eu

log_file="${XDG_RUNTIME_DIR:?}/pit-wall-fixture.log"
test -s "$log_file"
for expected in schedule driver-standings constructor-standings drivers session position intervals race-control; do
  grep -Fx "$expected" "$log_file" >/dev/null
done
