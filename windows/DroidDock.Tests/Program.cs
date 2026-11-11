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

PhoneEntry Target(string id, bool folder = false) => new("\\storage\\" + id, id, folder, 4, new DateTime(2026, 11, 1), id, "persistent-" + id);
int calls = 0;
var cancelledDelete = await FileDeletion.Run([Target("a")], false, _ => { calls++; return Task.CompletedTask; });
Check(calls == 0 && cancelledDelete.Deleted.Count == 0, "Cancel must never touch the backend");
foreach (PhoneEntry[] invalid in new[] { new[] { Target("a"), Target("folder", true) }, new[] { Target("a"), Target("a") } })
{
    var rejected = await FileDeletion.Run(invalid, true, _ => { calls++; return Task.CompletedTask; });
    Check(calls == 0 && rejected.Failure is not null, "Reject entire invalid selection before deleting anything");
}
var attempted = new List<string>();
var partial = await FileDeletion.Run([Target("a"), Target("b"), Target("c")], true, entry => {
    attempted.Add(entry.ObjectId);
    if (entry.ObjectId == "b") throw new IOException("Disconnected");
    return Task.CompletedTask;
});
Check(attempted.SequenceEqual(new[] { "a", "b" }) && partial.Deleted.Count == 1 && partial.Failure is not null,
    "A failure must preserve completed results and stop the batch");
bool stopDelete = false;
var stopped = await FileDeletion.Run([Target("a"), Target("b")], true,
    _ => { stopDelete = true; return Task.CompletedTask; }, () => stopDelete);
Check(stopped.Stopped && stopped.Deleted.Count == 1, "Stop finishes the current deletion only");
FileDeletion.RequireMatch(Target("a"), Target("a"));
foreach (var changed in new[] { Target("b"), Target("a") with { Bytes = 400 }, Target("a") with { IsFolder = true },
    Target("a") with { Path = "\\other\\a" }, Target("a") with { ObjectId = "replacement" } })
    await Fails<IOException>(() => { FileDeletion.RequireMatch(Target("a"), changed); return Task.CompletedTask; });
var mixed = new[] {
    Target("photo.jpg"), Target("document.pdf") with { Modified = new DateTime(2026, 11, 30) },
    Target("old.mp4") with { Modified = new DateTime(2025, 11, 1) }, Target("unknown") with { Modified = null } };
var groups = mixed.GroupBy(FileMonths.Key).OrderByDescending(g => g.Key).ToArray();
Check(groups.Length == 3 && groups[0].Count() == 2 && groups[1].Key == 202511 && groups[2].Key == 0,
    "All file types group by month and year, with unknown dates last");
Console.WriteLine("PASS: cancelled deletion, folder/duplicate rejection, partial failure, stopping, changed-file checks, and monthly grouping.");
