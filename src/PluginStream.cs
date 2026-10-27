using System;
using System.Collections.Concurrent;
using System.IO;
using System.Threading.Tasks;

public sealed class WebbyPluginStream
{
    public readonly ConcurrentQueue<string> Events = new ConcurrentQueue<string>();
    public volatile bool Closed;
    public string Status { get { return Closed ? "Plugin disconnected" : "Connected through OpenCode plugin"; } }
    public WebbyPluginStream()
    {
        Task.Run((Action)(() => {
            try {
                string line;
                while ((line = Console.In.ReadLine()) != null) {
                    if (line.Length > 1048576 || Events.Count >= 512) break;
                    Events.Enqueue(line);
                }
            } catch (IOException) { }
            finally { Closed = true; }
        }));
    }
    public void Dispose() { }
}
