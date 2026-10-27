import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

// OpenCode v2's Plugin.define is an identity helper. The equivalent object
// avoids a runtime package dependency for local directory installations.
export default {
  id: 'webby',
  setup(ctx) {
    if (process.platform !== 'win32') return
    const script = path.join(path.dirname(fileURLToPath(import.meta.url)), 'Spider.ps1')
    const child = spawn('powershell.exe', [
      '-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
      '-File', script, '-PluginMode', '-ProjectDirectory', ctx.location.directory,
    ], { windowsHide: true, stdio: ['pipe', 'ignore', 'ignore'] })
    const controller = new AbortController()
    let closed = false
    child.on('error', () => { closed = true; controller.abort() })
    child.on('exit', () => { closed = true; controller.abort() })
    child.stdin.on('error', () => { closed = true; controller.abort() })
    function send(event) {
      if (closed || !child.stdin.writable) return
      if (child.stdin.writableLength > 524288) { closed = true; controller.abort(); child.stdin.destroy(); return }
      child.stdin.write(JSON.stringify(event) + '\n')
    }
    send({ type: 'server.connected', data: {} })
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal, types: [
          'session.execution.started', 'session.execution.succeeded', 'session.execution.failed',
          'session.execution.interrupted', 'session.deleted', 'session.text.delta',
          'session.reasoning.started', 'session.tool.input.started', 'permission.asked', 'permission.replied',
        ] })) send(event)
      } catch { /* Aborting the subscription is expected during unload. */ }
    })()
    return () => {
      closed = true
      controller.abort()
      child.stdin.end()
    }
  },
}
