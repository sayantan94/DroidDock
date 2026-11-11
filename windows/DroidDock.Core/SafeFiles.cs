namespace DroidDock.Core;

public static class SafeFiles
{
    public static string Name(string input)
    {
        const string invalid = "<>:\"/\\|?*";
        string name = new(input.Select(c => c < 32 || invalid.Contains(c) ? '_' : c).ToArray());
        name = name.Trim().TrimEnd('.');
        if (string.IsNullOrWhiteSpace(name)) name = "Untitled";
        var stem = name.Split('.')[0].ToUpperInvariant();
        if (new[] { "CON", "PRN", "AUX", "NUL" }.Contains(stem) ||
            (stem.Length == 4 && (stem.StartsWith("COM") || stem.StartsWith("LPT")) && stem[3] is >= '1' and <= '9')) name = "_" + name;
        if (name.Length > 180) name = name[..160] + Path.GetExtension(name)[..Math.Min(20, Path.GetExtension(name).Length)];
        return name;
    }

    public static string Numbered(string name, int number) => number == 1 ? name :
        $"{Path.GetFileNameWithoutExtension(name)} ({number}){Path.GetExtension(name)}";

    public static void RequireRegularFile(string path)
    {
        var info = new FileInfo(path);
        if (!info.Exists || (info.Attributes & (FileAttributes.ReparsePoint | FileAttributes.Directory)) != 0)
            throw new IOException("Choose a regular file, not a shortcut, link, or folder.");
    }

    public static async Task<string> DownloadAsync(string destination, PhoneEntry entry, Func<string, Task> download)
    {
        Directory.CreateDirectory(destination);
        // Staging stays on the destination volume so the final no-overwrite rename is atomic.
        var stage = Path.Combine(destination, ".droiddock-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(stage);
        var temporary = Path.Combine(stage, "download");
        try
        {
            await download(temporary);
            RequireRegularFile(temporary);
            if ((ulong)new FileInfo(temporary).Length != entry.Bytes)
                throw new IOException("The downloaded file is incomplete. The original has not been changed.");
            if (entry.Modified is { } modified) File.SetLastWriteTime(temporary, modified);
            var name = Name(entry.Name);
            for (int number = 1; ; number++)
            {
                var target = Path.Combine(destination, Numbered(name, number));
                try { File.Move(temporary, target, overwrite: false); return target; }
                catch (IOException) when (File.Exists(target) || Directory.Exists(target)) { }
            }
        }
        finally { if (Directory.Exists(stage)) Directory.Delete(stage, recursive: true); }
    }
}
