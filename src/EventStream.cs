using System;
using System.Collections.Concurrent;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

// Background IO only. WPF and the state reducer stay on the UI thread.
public sealed class SpiderEventStream : IDisposable
{
    public readonly ConcurrentQueue<string> Events = new ConcurrentQueue<string>();
    public volatile string Status = "Connecting";
    private volatile bool stopped;
    private HttpWebRequest request;
    private readonly string url;
    private readonly string authorization;

    public SpiderEventStream(string url, string username, string password)
    {
        this.url = url;
        if (!String.IsNullOrEmpty(password))
            authorization = "Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes(username + ":" + password));
        Task.Run((Action)Run);
    }

    private void Enqueue(string data)
    {
        // Bound memory if the desktop is blocked or the server is unusually busy.
        if (Events.Count >= 512) throw new IOException("Event queue overflow");
        Events.Enqueue(data);
    }

    private void Run()
    {
        while (!stopped)
        {
            try
            {
                request = (HttpWebRequest)WebRequest.Create(url.TrimEnd('/') + "/api/event");
                request.Proxy = null;
                request.AllowAutoRedirect = false;
                request.Timeout = 5000;
                request.ReadWriteTimeout = 30000;
                request.Accept = "text/event-stream";
                if (authorization != null) request.Headers[HttpRequestHeader.Authorization] = authorization;
                using (var response = (HttpWebResponse)request.GetResponse())
                using (var reader = new StreamReader(response.GetResponseStream()))
                {
                    Status = "Connected";
                    var data = new StringBuilder();
                    string line;
                    while (!stopped && (line = reader.ReadLine()) != null)
                    {
                        if (line.Length == 0)
                        {
                            if (data.Length > 0) { Enqueue(data.ToString()); data.Clear(); }
                        }
                        else if (line.StartsWith("data:", StringComparison.Ordinal))
                        {
                            if (data.Length > 0) data.Append('\n');
                            data.Append(line.Substring(5).TrimStart(' '));
                            if (data.Length > 1048576) throw new IOException("Oversized event");
                        }
                    }
                }
                Status = "Disconnected - retrying";
            }
            catch (WebException ex)
            {
                var response = ex.Response as HttpWebResponse;
                Status = response != null && (response.StatusCode == HttpStatusCode.Unauthorized || response.StatusCode == HttpStatusCode.Forbidden)
                    ? "Authentication required (see README)" : "Offline - retrying";
                if (response != null) response.Dispose();
            }
            catch (IOException) { Status = "Stream interrupted - retrying"; }
            catch (ObjectDisposedException) { Status = "Disconnected"; }
            finally { if (request != null) request.Abort(); }
            string discarded;
            while (Events.TryDequeue(out discarded)) { }
            Events.Enqueue("{\"type\":\"transport.disconnected\",\"data\":{}}");
            for (int i = 0; i < 30 && !stopped; i++) Thread.Sleep(100);
        }
    }

    public void Dispose()
    {
        stopped = true;
        if (request != null) request.Abort();
    }
}
