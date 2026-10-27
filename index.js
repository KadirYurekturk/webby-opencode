import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

// OpenCode v2's Plugin.define is an identity helper. The equivalent object
// avoids a runtime package dependency for local directory installations.
export default {
  id: 'webby',
  setup(ctx) {
    if (!['win32', 'linux', 'darwin'].includes(process.platform)) return
    if (process.platform === 'linux' && !process.env.DISPLAY) return
    const root = path.dirname(fileURLToPath(import.meta.url))
    const windows = process.platform === 'win32'
    const command = windows ? 'powershell.exe' : 'python3'
    const args = windows ? [
      '-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
      '-File', path.join(root, 'Spider.ps1'), '-PluginMode', '-ProjectDirectory', ctx.location.directory,
    ] : [path.join(root, 'src', 'desktop.py')]
    const child = spawn(command, args, { windowsHide: true, stdio: ['pipe', 'ignore', 'ignore'] })
    const controller = new AbortController()
    let closed = false
    child.on('error', () => { if (!closed) console.warn('Webby could not start; see the README for platform requirements.'); closed = true; controller.abort() })
    child.on('exit', (code) => { if (!closed && code !== 0) console.warn('Webby exited unexpectedly; see the README for platform requirements.'); closed = true; controller.abort() })
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
