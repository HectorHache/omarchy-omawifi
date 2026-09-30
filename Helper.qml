import QtQuick
import Quickshell
import Quickshell.Io

// Runs the plugin's own omawifi script and hands back its stdout.
//
// One call at a time on purpose. Every command here touches the same radio and
// the same NetworkManager profile, and a bind takes a couple of seconds while
// the link drops, so overlapping runs would fight each other for no gain.
//
// Two kinds of caller, two kinds of request. A poll (the timed `ui` read) is
// disposable: if something is already running, dropping it costs nothing
// because the next tick is a few seconds away. An action is what the user just
// asked for, so it is queued in a single slot instead of being refused: a click
// that lands 40 ms into a poll must still happen, it must just happen next.
QtObject {
  id: root

  property string script: ""
  property var environment: ({})
  property string interpreter: "/usr/bin/bash"

  readonly property bool busy: proc.running
  property string runningOp: ""

  property string _pendingOp: ""
  property var _pendingArgs: []

  // True while a caller-visible action is in flight (anything but a poll), so
  // the UI can say "working" without flickering on every background read.
  readonly property bool acting: (proc.running && root.runningOp !== "ui") || root._pendingOp !== ""

  // op is a word the caller chose ("ui", "bind", "auto", "switch"); it comes
  // back on the signal so one handler can serve them all.
  signal finished(string op, int code, string out, string err)

  function run(op, args, queued) {
    var command = [root.interpreter, root.script]
    for (var i = 0; i < (args || []).length; i++) command.push(String(args[i]))
    if (proc.running) {
      if (!queued) return false
      root._pendingOp = op
      root._pendingArgs = command
      return true
    }
    root._start(op, command)
    return true
  }

  function _start(op, command) {
    proc.command = command
    proc.environment = root.environment || ({})
    root.runningOp = op
    _code = -1
    proc.running = true
  }

  property int _code: -1
  property string _op: ""

  // The process is held in a property rather than declared as a child: a
  // QtObject has no default property, so a direct child would not compile.
  property Process proc: Process {
    id: proc
    command: []
    stdout: StdioCollector { id: out; waitForEnd: true }
    stderr: StdioCollector { id: err; waitForEnd: true }
    onStarted: root._op = root.runningOp
    onExited: function (code) { root._code = code }
    onRunningChanged: {
      if (proc.running) return
      // onExited has already run by the time the process stops; a stop without
      // it (killed from outside) is reported as a failure rather than a hang.
      var code = root._code === -1 ? 130 : root._code
      var op = root._op
      var outText = out.text
      var errText = err.text
      root._code = -1
      root._op = ""
      root.runningOp = ""
      // Hand the slot over before reporting, so a handler that starts the next
      // command itself (a refresh after a bind) is not refused by a stale busy.
      var nextOp = root._pendingOp
      var nextArgs = root._pendingArgs
      root._pendingOp = ""
      root._pendingArgs = []
      if (nextOp !== "") root._start(nextOp, nextArgs)
      root.finished(op, code, outText, errText)
    }
  }
}
