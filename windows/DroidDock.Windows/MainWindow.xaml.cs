using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DroidDock.Core;
using Microsoft.Win32;

namespace DroidDock.Windows;

public partial class MainWindow : Window
{
    private readonly PhoneService phone = new();
    private readonly bool demo;
    private readonly string? screenshot;
    private bool connected, busy, transferring, stop, closing;
    private string folder = "\\";
    private string destination = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "DroidDock");
    private IReadOnlyList<PhoneEntry> entries = [];
    private Dictionary<string, FolderTotal> sizes = new(StringComparer.OrdinalIgnoreCase);
    private CancellationTokenSource? sizeScan;

    public MainWindow(string[] args)
    {
        InitializeComponent();
        demo = args.Contains("--demo") || args.Contains("--screenshot");
        int index = Array.IndexOf(args, "--screenshot");
        screenshot = index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
        Loaded += async (_, _) =>
        {
            if (!demo) return;
            DemoLabel.Visibility = Visibility.Visible;
            DeviceLabel.Text = "Sample Android phone";
            ConnectionLabel.Text = "Sample library · no phone accessed";
            connected = true; ConnectButton.IsEnabled = false;
            await Navigate("\\Internal storage");
            if (screenshot is not null)
            {
                await Task.Delay(500);
                UpdateLayout();
                var bitmap = new RenderTargetBitmap((int)CanvasRoot.ActualWidth, (int)CanvasRoot.ActualHeight, 96, 96, PixelFormats.Pbgra32);
                bitmap.Render(CanvasRoot);
                var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(screenshot))!);
                using (var output = File.Create(screenshot)) encoder.Save(output);
                Application.Current.Shutdown(0);
            }
        };
        Closing += Window_Closing;
    }

    private async Task Run(Func<Task> action)
    {
        if (busy) return;
        busy = true; UpdateControls();
        try { await action(); }
        catch (Exception error)
        {
            StatusLabel.Text = error.Message + " Unlock the phone and use Refresh or Connect to retry.";
        }
        finally { busy = false; UpdateControls(); }
    }

    private async void Connect_Click(object sender, RoutedEventArgs e) => await Run(async () =>
    {
        CancelScan(); connected = false; entries = []; ApplyFilter();
        StatusLabel.Text = "Connecting…";
        DeviceLabel.Text = await phone.Connect(); connected = true;
        ConnectionLabel.Text = "USB file transfer";
        await Load("\\");
    });

    private Task Navigate(string path) => Run(() => Load(path));
    private async Task Load(string path)
    {
        CancelScan();
        var contents = await List(path, CancellationToken.None);
        folder = path; entries = contents; SearchBox.Text = "";
        PathLabel.Text = path == "\\" ? "Phone storage" : path.TrimStart('\\').Replace("\\", "  ›  ");
        StatusLabel.Text = demo ? "Sample files for this preview. Connect your phone to transfer real files." : "Double-click a folder to open it. Select files to copy, or send files into this folder.";
        ApplyFilter(); StartScan();
    }

    private Task<IReadOnlyList<PhoneEntry>> List(string path, CancellationToken token) => demo
        ? Task.FromResult(DemoFiles.List(path)) : phone.List(path, token);

    private void CancelScan()
    {
        sizeScan?.Cancel(); sizeScan?.Dispose(); sizeScan = null; sizes.Clear();
    }

    private async void StartScan()
    {
        CancelScan();
        var scan = new CancellationTokenSource(); sizeScan = scan;
        var token = scan.Token;
        var scanFolder = folder; var initial = entries;
        SizeLabel.Text = "Calculating folder size…";
        try
        {
            var totals = await FolderSizes.CalculateAsync(scanFolder,
                (path, ct) => path == scanFolder ? Task.FromResult(initial) : List(path, ct), token);
            if (sizeScan != scan || token.IsCancellationRequested) return;
            sizes = totals;
            var total = totals[scanFolder];
            SizeLabel.Text = $"{FolderSizes.Format(total.Bytes)} total · {total.Files:N0} files";
            ApplyFilter();
        }
        catch (OperationCanceledException) { }
        catch (Exception)
        {
            if (sizeScan == scan) SizeLabel.Text = "Folder size unavailable · use Refresh to retry";
        }
    }

    private void ApplyFilter()
    {
        if (FilesGrid is null) return;
        var query = SearchBox.Text.Trim();
        var selectedPaths = FilesGrid.SelectedItems.Cast<FileRow>().Select(r => r.Entry.Path).ToHashSet();
        var rows = entries.Where(e => e.Name.Contains(query, StringComparison.CurrentCultureIgnoreCase))
            .Select(e => new FileRow(e, e.IsFolder ? sizes.TryGetValue(e.Path, out var size) ? FolderSizes.Format(size.Bytes) : "—" : FolderSizes.Format(e.Bytes))).ToList();
        FilesGrid.ItemsSource = rows;
        foreach (var row in rows.Where(r => selectedPaths.Contains(r.Entry.Path))) FilesGrid.SelectedItems.Add(row);
        CountLabel.Text = $"{rows.Count} items · totals include all subfolders";
        UpdateControls();
    }

    private void UpdateControls()
    {
        if (CopyButton is null) return;
        ConnectButton.IsEnabled = !busy && !demo;
        HomeButton.IsEnabled = RefreshButton.IsEnabled = connected && !busy;
        UpButton.IsEnabled = connected && !busy && folder != "\\";
        FilesGrid.IsEnabled = !busy;
        DestinationButton.IsEnabled = !busy;
        CopyButton.IsEnabled = connected && !demo && !busy && FilesGrid.SelectedItems.Cast<FileRow>().Any(r => !r.Entry.IsFolder);
        SendButton.IsEnabled = connected && !demo && !busy && folder != "\\";
    }

    private async void Home_Click(object sender, RoutedEventArgs e) => await Navigate("\\");
    private async void Up_Click(object sender, RoutedEventArgs e)
    {
        var trimmed = folder.TrimEnd('\\'); int index = trimmed.LastIndexOf('\\');
        await Navigate(index <= 0 ? "\\" : trimmed[..index]);
    }
    private async void Refresh_Click(object sender, RoutedEventArgs e) => await Navigate(folder);
    private void Search_Changed(object sender, TextChangedEventArgs e) => ApplyFilter();
    private void Files_SelectionChanged(object sender, SelectionChangedEventArgs e) => UpdateControls();
    private async void Files_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (!busy && FilesGrid.SelectedItem is FileRow { Entry.IsFolder: true } row) await Navigate(row.Entry.Path);
    }
    private void Destination_Click(object sender, RoutedEventArgs e)
    {
        var picker = new OpenFolderDialog { Title = "Choose where to copy your files", InitialDirectory = Directory.Exists(destination) ? destination : Environment.GetFolderPath(Environment.SpecialFolder.MyPictures) };
        if (picker.ShowDialog(this) == true) { destination = picker.FolderName; DestinationLabel.Text = destination; }
    }

    private async void Copy_Click(object sender, RoutedEventArgs e)
    {
        var selected = FilesGrid.SelectedItems.Cast<FileRow>().Select(r => r.Entry).Where(e => !e.IsFolder).ToArray();
        if (demo || selected.Length == 0) return;
        await Run(async () =>
        {
            BeginTransfer(); int completed = 0;
            try
            {
                foreach (var entry in selected)
                {
                    if (stop) break;
                    StatusLabel.Text = $"Copying {completed + 1} of {selected.Length} · {entry.Name}";
                    await SafeFiles.DownloadAsync(destination, entry, temporary => phone.Download(entry, temporary));
                    completed++;
                }
                StatusLabel.Text = $"{completed} files copied to your PC{(stop ? " · Stopped" : "")}.";
            }
            catch (Exception error) { throw new IOException($"{completed} files copied. {error.Message}", error); }
            finally { EndTransfer(); StartScan(); }
        });
    }

    private async void Send_Click(object sender, RoutedEventArgs e)
    {
        if (demo) return;
        var picker = new OpenFileDialog { Title = "Send files to the open phone folder", Multiselect = true, CheckFileExists = true };
        if (picker.ShowDialog(this) != true) return;
        await Run(async () =>
        {
            BeginTransfer(); int completed = 0;
            try
            {
                foreach (var source in picker.FileNames)
                {
                    if (stop) break;
                    StatusLabel.Text = $"Sending {completed + 1} of {picker.FileNames.Length} · {Path.GetFileName(source)}";
                    await phone.Upload(source, folder); completed++;
                }
                await Load(folder);
                StatusLabel.Text = $"{completed} files sent to your phone{(stop ? " · Stopped" : "")}.";
            }
            catch (Exception error) { throw new IOException($"{completed} files sent. {error.Message} Check the phone for any incomplete copy before retrying.", error); }
            finally { EndTransfer(); StartScan(); }
        });
    }

    private void BeginTransfer()
    {
        CancelScan(); SizeLabel.Text = "Folder size paused during transfer";
        transferring = true; stop = false;
        Progress.Visibility = StopButton.Visibility = Visibility.Visible;
        Progress.IsIndeterminate = true; StopButton.Content = "Stop after this file"; StopButton.IsEnabled = true;
    }
    private void EndTransfer() { transferring = false; Progress.Visibility = StopButton.Visibility = Visibility.Collapsed; }
    private void Stop_Click(object sender, RoutedEventArgs e) { stop = true; StopButton.Content = "Finishing this file…"; StopButton.IsEnabled = false; }
    private async void Window_Closing(object? sender, CancelEventArgs e)
    {
        if (closing) return;
        e.Cancel = true;
        if (transferring)
        {
            MessageBox.Show(this, "Use Stop after this file and wait for copying to finish before closing DroidDock.", "Transfer in progress"); return;
        }
        if (busy) { StatusLabel.Text = "Wait for the current phone operation to finish before closing."; return; }
        CancelScan(); busy = true; UpdateControls();
        try { if (!demo) await phone.Disconnect(); }
        finally { closing = true; Close(); }
    }
}

public record FileRow(PhoneEntry Entry, string Size)
{
    public string DisplayName => (Entry.IsFolder ? "▣  " : "◇  ") + Entry.Name;
    public string Modified => Entry.Modified?.ToString("MMM d, yyyy") ?? "—";
}

internal static class DemoFiles
{
    private static readonly DateTime date = new(2026, 11, 10);
    public static IReadOnlyList<PhoneEntry> List(string path)
    {
        string root = "\\Internal storage";
        if (path == "\\") return [new(root, "Internal storage", true, 0)];
        if (path == root) return [
            new(root + "\\DCIM", "DCIM", true, 0, date), new(root + "\\Documents", "Documents", true, 0, date),
            new(root + "\\Download", "Download", true, 0, date), new(root + "\\Music", "Music", true, 0, date),
            new(root + "\\Pictures", "Pictures", true, 0, date), new(root + "\\notes.txt", "notes.txt", false, 2400, date)];
        if (path.EndsWith("DCIM")) return [new(path + "\\Camera", "Camera", true, 0, date)];
        (string name, ulong size)[] files = path.EndsWith("Camera") ? [("Morning.jpg", 4200000), ("Trail.mp4", 325000000)] :
            path.EndsWith("Documents") ? [("Trip.pdf", 840000)] : path.EndsWith("Download") ? [("Map.pdf", 12500000)] :
            path.EndsWith("Music") ? [("Acoustic.flac", 24600000)] : [("Landscape.png", 3250000)];
        return files.Select(f => new PhoneEntry(path + "\\" + f.name, f.name, false, f.size, date)).ToList();
    }
}
