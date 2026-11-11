using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using DroidDock.Core;

namespace DroidDock.Windows;
internal sealed class DeleteConfirmation : Window
{
    public DeleteConfirmation(Window owner, string device, string folder, IReadOnlyList<PhoneEntry> files)
    {
        Owner = owner; Title = "Delete from phone"; Width = 560; Height = 450;
        ResizeMode = ResizeMode.NoResize; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = new SolidColorBrush(Color.FromRgb(250, 251, 248));
        var panel = new DockPanel { Margin = new Thickness(24) };
        var heading = new StackPanel(); DockPanel.SetDock(heading, Dock.Top);
        heading.Children.Add(new TextBlock { Text = $"Delete {files.Count} {(files.Count == 1 ? "file" : "files")} from your phone?", FontSize = 23, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        heading.Children.Add(new TextBlock { Text = device + " · " + folder, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 12) });
        heading.Children.Add(new TextBlock { Text = "These files will be permanently deleted from the phone. They will not go to the Recycle Bin, and DroidDock cannot undo this. Copies on your PC are kept.", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 16) });
        panel.Children.Add(heading);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        DockPanel.SetDock(buttons, Dock.Bottom);
        var cancel = new Button { Content = "Cancel", IsCancel = true, IsDefault = true };
        cancel.Click += (_, _) => DialogResult = false;
        var confirm = new Button { Content = "Delete permanently", Background = Brushes.Firebrick, Foreground = Brushes.White };
        confirm.Click += (_, _) => DialogResult = true;
        buttons.Children.Add(cancel); buttons.Children.Add(confirm); panel.Children.Add(buttons);
        panel.Children.Add(new ListBox { ItemsSource = files.Select(f => $"{f.Name}  ({FolderSizes.Format(f.Bytes)})"),
            BorderThickness = new Thickness(1), Padding = new Thickness(8) });
        Content = panel;
        Loaded += (_, _) => cancel.Focus();
    }
}
