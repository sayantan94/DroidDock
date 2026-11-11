namespace DroidDock.Core;

public record PhoneEntry(string Path, string Name, bool IsFolder, ulong Bytes, DateTime? Modified = null);
public record FolderTotal(ulong Bytes, int Files);

public static class FolderSizes
{
    public static async Task<Dictionary<string, FolderTotal>> CalculateAsync(string root,
        Func<string, CancellationToken, Task<IReadOnlyList<PhoneEntry>>> list, CancellationToken token)
    {
        var order = new List<string> { root };
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { root };
        var parents = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var totals = new Dictionary<string, FolderTotal>(StringComparer.OrdinalIgnoreCase);
        for (int i = 0; i < order.Count; i++)
        {
            token.ThrowIfCancellationRequested();
            var folder = order[i];
            ulong bytes = 0; int files = 0;
            foreach (var entry in await list(folder, token))
            {
                token.ThrowIfCancellationRequested();
                if (entry.IsFolder)
                {
                    if (!seen.Add(entry.Path)) throw new IOException("Phone reported a repeated folder. Reconnect and retry.");
                    parents[entry.Path] = folder; order.Add(entry.Path);
                }
                else { bytes = checked(bytes + entry.Bytes); files++; }
            }
            totals[folder] = new(bytes, files);
        }
        foreach (var folder in order.AsEnumerable().Reverse())
        {
            token.ThrowIfCancellationRequested();
            if (parents.TryGetValue(folder, out var parent))
            {
                var a = totals[parent]; var b = totals[folder];
                totals[parent] = new(checked(a.Bytes + b.Bytes), checked(a.Files + b.Files));
            }
        }
        return totals;
    }

    public static string Format(ulong bytes)
    {
        string[] units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"];
        double value = bytes; int i = 0;
        while (value >= 1000 && i < units.Length - 1) { value /= 1000; i++; }
        return $"{value:0.##} {units[i]}";
    }
}
