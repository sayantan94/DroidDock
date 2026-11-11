namespace DroidDock.Core;

public record DeletionResult(IReadOnlyList<PhoneEntry> Deleted, string? Failure, bool Stopped);
public static class FileDeletion
{
    public static void RequireMatch(PhoneEntry expected, PhoneEntry current)
    {
        if (expected.IsFolder || current.IsFolder || string.IsNullOrEmpty(expected.ObjectId) || expected != current)
            throw new IOException("This file changed since it was selected. Refresh the folder and select it again.");
    }

    public static async Task<DeletionResult> Run(IReadOnlyList<PhoneEntry> targets, bool confirmed,
        Func<PhoneEntry, Task> deleteVerified, Func<bool>? shouldStop = null,
        Action<int, PhoneEntry>? beforeDelete = null, Action<PhoneEntry>? didDelete = null)
    {
        if (!confirmed) return new([], null, false);
        if (targets.Any(t => t.IsFolder || string.IsNullOrEmpty(t.ObjectId) || string.IsNullOrEmpty(t.Path)) ||
            targets.Select(t => t.ObjectId).Distinct().Count() != targets.Count)
            return new([], "Select individual files once each. Folders cannot be deleted.", false);
        var deleted = new List<PhoneEntry>();
        foreach (var target in targets)
        {
            if (shouldStop?.Invoke() == true) return new(deleted, null, true);
            beforeDelete?.Invoke(deleted.Count, target);
            try { await deleteVerified(target); deleted.Add(target); didDelete?.Invoke(target); }
            catch (Exception error) { return new(deleted, $"{target.Name}: {error.Message}", false); }
        }
        return new(deleted, null, false);
    }
}
