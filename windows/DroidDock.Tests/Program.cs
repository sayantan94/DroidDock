using DroidDock.Core;

static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
static async Task Fails<T>(Func<Task> action) where T : Exception
{
    try { await action(); } catch (T) { return; }
    throw new Exception($"Expected {typeof(T).Name}");
}
var tree = new Dictionary<string, IReadOnlyList<PhoneEntry>> {
    ["root"] = [new("photo", "photo", false, 10), new("nested", "nested", true, 0), new("empty", "empty", true, 0)],
    ["nested"] = [new("video", "video", false, 8_000_000_000), new("zero", "zero", false, 0)], ["empty"] = [] };
var totals = await FolderSizes.CalculateAsync("root", (p, _) => Task.FromResult(tree[p]), default);
Check(totals["root"] == new FolderTotal(8_000_000_010, 3), "Nested totals must include large and empty files");
Check(totals["empty"] == new FolderTotal(0, 0), "Empty folder size");
await Fails<IOException>(() => FolderSizes.CalculateAsync("root", (_, _) => throw new IOException(), default));
await Fails<IOException>(() => FolderSizes.CalculateAsync("root", (_, _) => Task.FromResult<IReadOnlyList<PhoneEntry>>([new("root", "cycle", true, 0)]), default));
using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
await Fails<OperationCanceledException>(() => FolderSizes.CalculateAsync("root", (_, _) => throw new Exception("Must not list after cancellation"), cancelled.Token));

var destination = Path.Combine(Path.GetTempPath(), "DroidDockTests-" + Guid.NewGuid());
Directory.CreateDirectory(destination);
try
{
    await File.WriteAllTextAsync(Path.Combine(destination, "photo.jpg"), "old");
    var entry = new PhoneEntry("photo", "photo.jpg", false, 4);
    var saved = await SafeFiles.DownloadAsync(destination, entry, p => File.WriteAllTextAsync(p, "new!"));
    Check(Path.GetFileName(saved) == "photo (2).jpg", "Collision must use a numbered name");
    Check(await File.ReadAllTextAsync(Path.Combine(destination, "photo.jpg")) == "old", "Original must survive");
    await Fails<IOException>(() => SafeFiles.DownloadAsync(destination, entry, p => File.WriteAllTextAsync(p, "x")));
    Check(!Directory.EnumerateDirectories(destination).Any(), "Failed transfer must clean staging");
    var empty = await SafeFiles.DownloadAsync(destination, new("empty", "empty.txt", false, 0), p => File.WriteAllBytesAsync(p, []));
    Check(new FileInfo(empty).Length == 0, "Zero-byte files are valid");
    Check(!SafeFiles.Name("../../private\\photo.jpg").Contains('/'), "Unsafe slash removed");
    Check(SafeFiles.Name("CON.txt") == "_CON.txt", "Windows reserved filename escaped");
}
finally { Directory.Delete(destination, true); }
Console.WriteLine("PASS: recursive sizes, empty folders, unreadable folders, cycles, cancellation, collisions, partial downloads, empty files, and safe filenames.");
