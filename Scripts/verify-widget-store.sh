#!/usr/bin/env bash
set -euo pipefail
cd "${BASH_SOURCE[0]%/*}/.."
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/usagebeacon-widget-store.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
cat > "$work_dir/Probe.swift" <<'SWIFT'
import Foundation

@main
struct Probe {
    static func main() throws {
        let args = CommandLine.arguments
        let url = URL(fileURLWithPath: args[2])
        if args[1] == "write" {
            let revision = Double(args[3])!
            try UsageBeaconWidgetSnapshotStore.save(
                UsageBeaconWidgetSnapshot(updatedAt: Date(timeIntervalSince1970: revision), providers: []),
                to: url
            )
        } else {
            // Keep the reader alive across writes, as WidgetKit keeps its extension alive.
            while let expected = readLine() {
                guard let snapshot = UsageBeaconWidgetSnapshotStore.load(from: url),
                      snapshot.updatedAt.timeIntervalSince1970 == Double(expected) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                FileHandle.standardOutput.write(Data("ok\n".utf8))
            }
        }
    }
}
SWIFT
xcrun swiftc Sources/UsageBeaconShared/WidgetSnapshot.swift "$work_dir/Probe.swift" -o "$work_dir/probe"
python3 - "$work_dir" <<'PY'
import pathlib, select, subprocess, sys
root = pathlib.Path(sys.argv[1])
probe, snapshot = str(root / 'probe'), str(root / 'snapshot.json')
reader = subprocess.Popen([probe, 'read', snapshot], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
try:
    for revision in range(1, 11):
        subprocess.run([probe, 'write', snapshot, str(revision)], check=True, timeout=10)
        reader.stdin.write(f'{revision}\n')
        reader.stdin.flush()
        assert select.select([reader.stdout], [], [], 10)[0], 'Widget reader timed out'
        assert reader.stdout.readline() == 'ok\n', 'Persistent reader saw stale snapshot'
    reader.stdin.close()
    assert reader.wait(timeout=10) == 0
finally:
    if reader.poll() is None:
        reader.kill()
        reader.wait()
print('Verified 10 successive widget writes with a separate persistent reader process.')
PY
