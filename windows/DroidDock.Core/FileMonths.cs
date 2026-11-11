using System.Globalization;

namespace DroidDock.Core;
public static class FileMonths
{
    public static int Key(PhoneEntry entry) => entry.IsFolder ? int.MaxValue :
        entry.Modified is { } date ? date.Year * 100 + date.Month : 0;
    public static string Label(PhoneEntry entry) => entry.IsFolder ? "Folders" :
        entry.Modified?.ToString("MMMM yyyy", CultureInfo.CurrentCulture) ?? "Unknown date";
}
