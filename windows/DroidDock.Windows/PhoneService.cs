using DroidDock.Core;
using System.IO;
using MediaDevices;

namespace DroidDock.Windows;

// MediaDevices 2 marshals WPD calls onto its COM worker. This gate also orders
// our higher-level reads and transfers and never blocks WPF's dispatcher.
public sealed class PhoneService
{
    private readonly SemaphoreSlim gate = new(1);
    private MediaDevice? device;
    private async Task<T> Work<T>(Func<T> action, CancellationToken token = default)
    {
        await gate.WaitAsync(token);
        try { return await Task.Run(() => { token.ThrowIfCancellationRequested(); return action(); }, token); }
        finally { gate.Release(); }
    }
    private MediaDevice Device => device ?? throw new IOException("Phone disconnected. Reconnect and choose File transfer.");

    public Task<string> Connect() => Work(() =>
    {
        device?.Dispose(); device = null;
        var devices = MediaDeviceManager.Instance.GetDevices()?.ToList() ?? [];
        if (devices.Count != 1)
        {
            foreach (var candidate in devices) candidate.Dispose();
            throw new IOException(devices.Count == 0 ? "No phone found. Unlock your phone, choose File transfer in its USB notification, and reconnect." : "Connect one phone at a time, then try again.");
        }
        var selected = devices[0];
        try { selected.Connect(enableCache: false); device = selected; return selected.FriendlyName ?? selected.Description ?? "Android phone"; }
        catch { selected.Dispose(); throw; }
    });

    public Task<IReadOnlyList<PhoneEntry>> List(string path, CancellationToken token = default) => Work<IReadOnlyList<PhoneEntry>>(() =>
    {
        var folder = path == "\\" ? Device.GetRootDirectory() : Device.GetDirectoryInfo(path);
        return folder.EnumerateFileSystemInfos().Select(item => new PhoneEntry(item.FullName, item.Name,
            item is MediaDirectoryInfo, item.Length, item.LastWriteTime)).OrderByDescending(e => e.IsFolder)
            .ThenBy(e => e.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
    }, token);

    public Task Download(PhoneEntry entry, string temporary) => Work(() =>
    {
        Device.DownloadFile(entry.Path, temporary); return true;
    });

    public Task<string> Upload(string source, string folder) => Work(() =>
    {
        SafeFiles.RequireRegularFile(source);
        var names = Device.GetDirectoryInfo(folder).EnumerateFileSystemInfos().Select(e => e.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var original = SafeFiles.Name(Path.GetFileName(source));
        int number = 1; var name = original;
        while (names.Contains(name)) name = SafeFiles.Numbered(original, ++number);
        var target = folder.TrimEnd('\\') + "\\" + name;
        var expected = (ulong)new FileInfo(source).Length;
        Device.UploadFile(source, target);
        if (Device.GetFileInfo(target).Length != expected)
            throw new IOException($"The phone reported an incomplete copy of {name}. Check that file before retrying.");
        return name;
    });

    public Task Disconnect() => Work(() => { device?.Dispose(); device = null; return true; });
}
