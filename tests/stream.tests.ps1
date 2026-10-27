$ErrorActionPreference = 'Stop'
Add-Type -Path "$PSScriptRoot/../src/EventStream.cs"
Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
public sealed class SpiderTestServer : IDisposable {
    private readonly TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
    public int Port;
    public SpiderTestServer() {
        listener.Start(); Port = ((IPEndPoint)listener.LocalEndpoint).Port;
        Task.Run((Action)(() => {
            try {
                using (var client = listener.AcceptTcpClient())
                using (var stream = client.GetStream()) {
                    var reader = new StreamReader(stream);
                    string line; while ((line = reader.ReadLine()) != null && line != "") { }
                    var writer = new StreamWriter(stream, new UTF8Encoding(false)) { AutoFlush = true, NewLine = "\r\n" };
                    writer.Write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n");
                    writer.Write(": heartbeat\n\nevent: ignored-header\ndata: {\"type\":\"server.connected\",\n");
                    writer.Write("data: \"data\":{}}\n\n");
                    Thread.Sleep(1500);
                }
            } catch (SocketException) { } catch (IOException) { }
        }));
    }
    public void Dispose() { listener.Stop(); }
}
'@
$server = [SpiderTestServer]::new()
$stream = [SpiderEventStream]::new("http://127.0.0.1:$($server.Port)", 'opencode', '')
try {
    $seenConnected = $false; $seenDisconnected = $false
    $deadline = [datetime]::UtcNow.AddSeconds(7)
    do {
        $raw = ''
        while ($stream.Events.TryDequeue([ref]$raw)) {
            $event = $raw | ConvertFrom-Json
            if ($event.type -eq 'server.connected') { $seenConnected = $true }
            if ($event.type -eq 'transport.disconnected') { $seenDisconnected = $true }
        }
        Start-Sleep -Milliseconds 50
    } until (($seenConnected -and $seenDisconnected) -or [datetime]::UtcNow -gt $deadline)
    if (-not $seenConnected) { throw 'Multiline SSE event was not delivered' }
    if (-not $seenDisconnected) { throw 'EOF did not report disconnected' }
    'PASS: SSE comments, headers, multiline data, EOF/disconnect and disposal'
} finally { $stream.Dispose(); $server.Dispose() }
