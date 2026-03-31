#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Quick App Remover v1.5.1
.DESCRIPTION
    A high-speed uninstallation tool using C# registry discovery and WPF.
    Added: Official slogan "The multiple searching app removal tool." to UI and Guide.
    Credits: Created by Joshua Dwight.
#>

# Ensure script is running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("Please run this tool as Administrator.", "Admin Required", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    exit
}

# 1. C# Registry Manager (Raw data extraction)
$csharpCode = @"
using System;
using System.Collections.Generic;
using Microsoft.Win32;

public class AppInfoRaw {
    public string DisplayName { get; set; }
    public string Publisher { get; set; }
    public string UninstallString { get; set; }
    public string QuietUninstallString { get; set; }
}

public class AppManager {
    public static List<AppInfoRaw> GetInstalledApps() {
        var apps = new List<AppInfoRaw>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        string[] paths = {
            @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        };

        foreach (var path in paths) {
            SearchRegistry(Registry.LocalMachine, path, apps, seen);
            SearchRegistry(Registry.CurrentUser, path, apps, seen);
        }

        apps.Sort((a, b) => string.Compare(a.DisplayName, b.DisplayName, StringComparison.OrdinalIgnoreCase));
        return apps;
    }

    private static void SearchRegistry(RegistryKey root, string path, List<AppInfoRaw> apps, HashSet<string> seen) {
        try {
            using (RegistryKey key = root.OpenSubKey(path)) {
                if (key == null) return;
                foreach (string subkeyName in key.GetSubKeyNames()) {
                    try {
                        using (RegistryKey subkey = key.OpenSubKey(subkeyName)) {
                            if (subkey == null) continue;
                            string name = subkey.GetValue("DisplayName") as string;
                            string uninstall = subkey.GetValue("UninstallString") as string;
                            if (string.IsNullOrEmpty(name) || string.IsNullOrEmpty(uninstall)) continue;

                            if (seen.Add(name + uninstall)) {
                                apps.Add(new AppInfoRaw {
                                    DisplayName = name,
                                    Publisher = subkey.GetValue("Publisher") as string ?? "Unknown",
                                    UninstallString = uninstall,
                                    QuietUninstallString = subkey.GetValue("QuietUninstallString") as string
                                });
                            }
                        }
                    } catch {}
                }
            }
        } catch {}
    }
}
"@
try { Add-Type -TypeDefinition $csharpCode -ErrorAction Stop } catch {}

# Load UI Assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# 2. XAML UI Definition
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Quick App Remover v1.5.1 by Joshua Dwight" Height="850" Width="1100" WindowStartupLocation="CenterScreen" Background="#F9FAFB">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/> <!-- Menu Bar -->
            <RowDefinition Height="Auto"/> <!-- Header Section -->
            <RowDefinition Height="*"/>    <!-- Main Tabs -->
            <RowDefinition Height="130"/>  <!-- Log Area -->
        </Grid.RowDefinitions>

        <Menu Grid.Row="0" Background="#F3F4F6" BorderBrush="#E5E7EB" BorderThickness="0,0,0,1">
            <MenuItem Header="_File">
                <MenuItem Name="menuExit" Header="_Exit" InputGestureText="Alt+F4"/>
            </MenuItem>
            <MenuItem Header="_Help">
                <MenuItem Name="menuGuide" Header="_User Guide"/>
                <MenuItem Name="menuChangelog" Header="_Changelog"/>
                <Separator/>
                <MenuItem Name="menuAbout" Header="_About"/>
            </MenuItem>
        </Menu>

        <StackPanel Grid.Row="1" Margin="20,15,20,15">
            <TextBlock Text="Quick App Remover" FontSize="28" FontWeight="ExtraBold" Foreground="#111827"/>
            <TextBlock Text="The multiple searching app removal tool." FontSize="14" FontStyle="Italic" Foreground="#6B7280" Margin="2,2,0,0"/>
        </StackPanel>

        <TabControl Name="mainTabs" Grid.Row="2" Background="White" BorderBrush="#E5E7EB" BorderThickness="1" Margin="20,0,20,0">
            
            <TabItem Header="All Apps" FontSize="13" Padding="15,8">
                <Grid Margin="20">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <TextBlock Text="Filter &amp; Select Applications" Grid.Row="0" FontWeight="SemiBold" FontSize="18" Foreground="#111827" Margin="0,0,0,10"/>

                    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,15">
                        <StackPanel Margin="0,0,20,0">
                            <TextBlock Text="Filter by Name:" FontSize="12" Foreground="#6B7280" Margin="0,0,0,4"/>
                            <TextBox Name="txtFilterAllName" Width="250" Padding="8,5" FontSize="14" BorderBrush="#D1D5DB"/>
                        </StackPanel>
                        <StackPanel Margin="0,0,20,0">
                            <TextBlock Text="Filter by Publisher:" FontSize="12" Foreground="#6B7280" Margin="0,0,0,4"/>
                            <TextBox Name="txtFilterAllPublisher" Width="250" Padding="8,5" FontSize="14" BorderBrush="#D1D5DB"/>
                        </StackPanel>
                        <Button Name="btnClearFilters" Content="Clear Filters" Margin="0,20,0,0" Padding="15,0" Height="34" Background="#E5E7EB" Foreground="#374151" BorderThickness="0" Cursor="Hand">
                             <Button.Resources><Style TargetType="Border"><Setter Property="CornerRadius" Value="4"/></Style></Button.Resources>
                        </Button>
                    </StackPanel>

                    <DataGrid Name="dgAllApps" Grid.Row="2" AutoGenerateColumns="False" CanUserAddRows="False" Margin="0,0,0,15" 
                              SelectionMode="Extended" GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="#F3F4F6" RowBackground="White" AlternatingRowBackground="#F9FAFB">
                        <DataGrid.Columns>
                            <DataGridTemplateColumn Header="Select" Width="60">
                                <DataGridTemplateColumn.CellTemplate>
                                    <DataTemplate>
                                        <CheckBox IsChecked="{Binding IsSelected, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" 
                                                  HorizontalAlignment="Center" VerticalAlignment="Center" IsHitTestVisible="False"/>
                                    </DataTemplate>
                                </DataGridTemplateColumn.CellTemplate>
                            </DataGridTemplateColumn>
                            <DataGridTextColumn Header="Application Name" Binding="{Binding DisplayName}" Width="*" IsReadOnly="True"/>
                            <DataGridTextColumn Header="Publisher" Binding="{Binding Publisher}" Width="350" IsReadOnly="True"/>
                        </DataGrid.Columns>
                    </DataGrid>

                    <Button Name="btnUninstallSelected" Grid.Row="3" Content="Uninstall Selected Apps" Background="#EF4444" Foreground="White" FontWeight="Bold" FontSize="15" Height="50" Cursor="Hand" BorderThickness="0">
                        <Button.Resources><Style TargetType="Border"><Setter Property="CornerRadius" Value="6"/></Style></Button.Resources>
                    </Button>
                </Grid>
            </TabItem>

            <TabItem Header="By Publisher" FontSize="13" Padding="15,8">
                <Grid Margin="20">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    
                    <DockPanel LastChildFill="True" Margin="0,0,0,20">
                        <TextBlock Text="Select Publisher:" VerticalAlignment="Center" FontWeight="SemiBold" FontSize="14" Margin="0,0,15,0"/>
                        <Button Name="btnRefreshAll" DockPanel.Dock="Right" Content="↻ Refresh List" Width="120" Margin="15,0,0,0" Padding="5" Background="#10B981" Foreground="White" FontWeight="Bold" Cursor="Hand" BorderThickness="0">
                            <Button.Resources><Style TargetType="Border"><Setter Property="CornerRadius" Value="4"/></Style></Button.Resources>
                        </Button>
                        <ComboBox Name="cmbPublishers" IsEditable="True" VerticalContentAlignment="Center"/>
                    </DockPanel>

                    <DataGrid Name="dgPublisherApps" Grid.Row="1" AutoGenerateColumns="False" IsReadOnly="True" Margin="0,0,0,15" GridLinesVisibility="Horizontal">
                        <DataGrid.Columns>
                            <DataGridTextColumn Header="Name" Binding="{Binding DisplayName}" Width="*"/>
                            <DataGridTextColumn Header="Publisher" Binding="{Binding Publisher}" Width="350"/>
                        </DataGrid.Columns>
                    </DataGrid>
                    <Button Name="btnUninstallPublisher" Grid.Row="2" Content="Uninstall All From Publisher" Background="#EF4444" Foreground="White" Height="50" FontWeight="Bold" Cursor="Hand" BorderThickness="0">
                         <Button.Resources><Style TargetType="Border"><Setter Property="CornerRadius" Value="6"/></Style></Button.Resources>
                    </Button>
                </Grid>
            </TabItem>

            <TabItem Header="By App Name" FontSize="13" Padding="15,8">
                <Grid Margin="20"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,20"><TextBlock Text="Search Name:" VerticalAlignment="Center" Margin="0,0,15,0"/><TextBox Name="txtSearchName" Width="300" Padding="5"/><Button Name="btnSearchName" Content="Search" Margin="15,0,0,0" Width="80" IsDefault="True"/></StackPanel>
                    <DataGrid Name="dgNameApps" Grid.Row="1" AutoGenerateColumns="False" IsReadOnly="True" Margin="0,0,0,15" GridLinesVisibility="Horizontal"><DataGrid.Columns><DataGridTextColumn Header="Name" Binding="{Binding DisplayName}" Width="*"/><DataGridTextColumn Header="Publisher" Binding="{Binding Publisher}" Width="350"/></DataGrid.Columns></DataGrid>
                    <Button Name="btnUninstallName" Grid.Row="2" Content="Uninstall Matching Name" Background="#EF4444" Foreground="White" Height="50" FontWeight="Bold" BorderThickness="0"><Button.Resources><Style TargetType="Border"><Setter Property="CornerRadius" Value="6"/></Style></Button.Resources></Button></Grid>
            </TabItem>
            
            <TabItem Header="By Vendor" FontSize="13" Padding="15,8">
                <Grid Margin="20"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,20"><TextBlock Text="Search Vendor:" VerticalAlignment="Center" Margin="0,0,15,0"/><TextBox Name="txtSearchVendor" Width="300" Padding="5"/><Button Name="btnSearchVendor" Content="Search" Margin="15,0,0,0" Width="80" IsDefault="True"/></StackPanel>
                    <DataGrid Name="dgVendorApps" Grid.Row="1" AutoGenerateColumns="False" IsReadOnly="True" Margin="0,0,0,15" GridLinesVisibility="Horizontal"><DataGrid.Columns><DataGridTextColumn Header="Name" Binding="{Binding DisplayName}" Width="*"/><DataGridTextColumn Header="Publisher" Binding="{Binding Publisher}" Width="350"/></DataGrid.Columns></DataGrid>
                    <Button Name="btnUninstallVendor" Grid.Row="2" Content="Uninstall Matching Vendor" Background="#EF4444" Foreground="White" Height="50" FontWeight="Bold" BorderThickness="0"><Button.Resources><Style TargetType="Border"><Setter Property="CornerRadius" Value="6"/></Style></Button.Resources></Button></Grid>
            </TabItem>
        </TabControl>

        <TextBox Name="txtLog" Grid.Row="3" Margin="20,15,20,15" IsReadOnly="True" Background="#111827" Foreground="#10B981" FontFamily="Consolas" FontSize="13" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" Padding="10" Focusable="False"/>
    </Grid>
</Window>
"@

# 3. Code-Behind
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Map UI
$mainTabs = $window.FindName("mainTabs")
$menuExit = $window.FindName("menuExit")
$menuGuide = $window.FindName("menuGuide")
$menuChangelog = $window.FindName("menuChangelog")
$menuAbout = $window.FindName("menuAbout")
$dgAllApps = $window.FindName("dgAllApps")
$btnRefreshAll = $window.FindName("btnRefreshAll")
$txtFilterAllName = $window.FindName("txtFilterAllName")
$txtFilterAllPublisher = $window.FindName("txtFilterAllPublisher")
$btnClearFilters = $window.FindName("btnClearFilters")
$btnUninstallSelected = $window.FindName("btnUninstallSelected")
$cmbPublishers = $window.FindName("cmbPublishers")
$dgPublisherApps = $window.FindName("dgPublisherApps")
$btnUninstallPublisher = $window.FindName("btnUninstallPublisher")
$txtSearchName = $window.FindName("txtSearchName")
$btnSearchName = $window.FindName("btnSearchName")
$dgNameApps = $window.FindName("dgNameApps")
$btnUninstallName = $window.FindName("btnUninstallName")
$txtSearchVendor = $window.FindName("txtSearchVendor")
$btnSearchVendor = $window.FindName("btnSearchVendor")
$dgVendorApps = $window.FindName("dgVendorApps")
$btnUninstallVendor = $window.FindName("btnUninstallVendor")
$txtLog = $window.FindName("txtLog")

Function Update-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "HH:mm:ss"
    $txtLog.AppendText("[$timestamp] $Message`n")
    $txtLog.ScrollToEnd()
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{ $frame.Continue = $false }) | Out-Null
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

Function Show-UserGuide {
    $guideContent = @"
QUICK APP REMOVER
"The multiple searching app removal tool."
-----------------------------------
This tool helps you quickly clean up your computer by removing many apps at once.

1. THE "ALL APPS" TAB (Your Command Center)
   - This tab lists every app on your computer.
   - CHECKBOXES: Click the little box next to an app to mark it for removal.
   - POWER SEARCH: Type in 'Filter by Name' to find an app (like 'Java').
   - MULTIPLE SEARCHES: You can search for 'Java', check it, then search for 'Adobe' and check that too. The tool remembers everything you checked, even when you change your search!
   - BULK SELECT: Click an app, then hold 'Control' and press 'A' on your keyboard to highlight everything. Click any checkbox in that list to check them all at once.

2. OTHER TABS
   - BY PUBLISHER: Pick a company (like Microsoft) and see all their apps.
   - BY APP NAME/VENDOR: Use these if you want to find things using special 'wildcards' (automatic search).

3. HOW TO UNINSTALL
   - Once you have checked everything you want to remove, click the big red button at the bottom.
   - The tool will go through the list one by one and remove them quietly without bothering you.

4. KEYBOARD SHORTCUTS (For Faster Work)
   - Control + 1: Go to All Apps
   - Control + 2: Go to Publisher List
   - Control + 3: Search by Name
   - Control + 4: Search by Vendor
   - Enter: Press this after typing a search to find apps instantly.
"@

    $guideXaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Title='User Guide' Height='600' Width='700' WindowStartupLocation='CenterOwner'>
    <Grid Margin='15'>
        <TextBox Name='txtGuide' IsReadOnly='True' TextWrapping='Wrap' VerticalScrollBarVisibility='Auto' FontFamily='Segoe UI' FontSize='14' Padding='15' BorderBrush='#D1D5DB'/>
    </Grid>
</Window>
"@
    $gWin = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$guideXaml)))
    $gWin.FindName("txtGuide").Text = $guideContent
    $gWin.Owner = $window
    [void]$gWin.ShowDialog()
}

Function Show-About {
    $aboutXaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Title='About' Height='250' Width='400' WindowStartupLocation='CenterOwner' ResizeMode='NoResize'>
    <StackPanel Margin='20' HorizontalAlignment='Center' VerticalAlignment='Center'>
        <TextBlock Text='Quick App Remover' FontSize='20' FontWeight='Bold' Margin='0,0,0,5' HorizontalAlignment='Center'/>
        <TextBlock Text='The multiple searching app removal tool.' FontSize='12' FontStyle='Italic' Foreground='#6B7280' Margin='0,0,0,10' HorizontalAlignment='Center'/>
        <TextBlock Text='v1.5.1' Margin='0,0,0,15' HorizontalAlignment='Center' Foreground='#6B7280'/>
        <TextBlock Text='Created by Joshua Dwight' FontSize='16' Margin='0,0,0,10' HorizontalAlignment='Center'/>
        <TextBlock Name='lnkGithub' Text='https://github.com/joshdwight101' Foreground='Blue' Cursor='Hand' TextDecorations='Underline' HorizontalAlignment='Center'/>
    </StackPanel>
</Window>
"@
    $aWin = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$aboutXaml)))
    $aWin.FindName("lnkGithub").Add_MouseDown({
        Start-Process "https://github.com/joshdwight101"
    })
    $aWin.Owner = $window
    [void]$aWin.ShowDialog()
}

Function Show-Changelog {
    $clContent = @"
Quick App Remover - Historical Changelog

v1.5.1 (Current)
- Added official slogan: "The multiple searching app removal tool."
- Integrated slogan into Header, About window, and User Guide.

v1.5.0
- Added 'User Guide' to the help menu for beginners and power users.
- Added 'About' window with clickable GitHub link.
- Final UI polish for help windows.

v1.4.8
- Fixed Changelog XAML parsing error caused by nested quote characters.
- Expanded full historical changelog data.

v1.4.7
- Implemented NoteProperty injection for selection logic. This fixes the 'Property not found' binder error.

v1.4.1 - v1.4.6
- Added global Menu Bar with File (Exit) and Help (Changelog) menus.
- Sequential uninstallation logic.
- Ctrl+A selection support for bulk checkbox toggling.
- Registry discovery optimizations.

v1.3.0 - v1.3.2
- Added real-time 'Filter-as-you-type' for All Apps.
- Selection persistence across filters.

v1.2.0
- Renamed application to 'Quick App Remover'.
- Introduced 'All Apps' tab.

v1.1.0
- Added branding, ToolTips, and Shortcuts (Ctrl+1-4).

v1.0.0
- Initial Build. C# Registry discovery.
"@

    $clXaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Title='Historical Changelog' Height='600' Width='700' WindowStartupLocation='CenterOwner'>
    <Grid Margin='15'>
        <TextBox Name='txtCL' IsReadOnly='True' TextWrapping='Wrap' VerticalScrollBarVisibility='Auto' FontFamily='Consolas' FontSize='12' Padding='10' BorderBrush='#D1D5DB'/>
    </Grid>
</Window>
"@
    $clWin = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$clXaml)))
    $clWin.FindName("txtCL").Text = $clContent 
    $clWin.Owner = $window
    [void]$clWin.ShowDialog()
}

Function Apply-AllAppsFilter {
    if (!$global:allAppsRaw) { return }
    $name = $txtFilterAllName.Text.Trim(); $pub = $txtFilterAllPublisher.Text.Trim()
    $dgAllApps.ItemsSource = [System.Collections.ArrayList]@($global:allAppsRaw | Where-Object { ($_.DisplayName -like "*$name*") -and ($_.Publisher -like "*$pub*") })
}

Function Refresh-AppList {
    Update-Log "--- Refreshing System Scan ---"
    $btnRefreshAll.IsEnabled = $false
    $raw = [AppManager]::GetInstalledApps()
    $global:allAppsRaw = foreach ($item in $raw) { $item | Select-Object *, @{N='IsSelected'; E={$false}} }
    Apply-AllAppsFilter
    $cmbPublishers.Items.Clear()
    ($global:allAppsRaw | Select-Object -ExpandProperty Publisher | Where-Object { $_ -and $_ -ne 'Unknown' } | Sort-Object -Unique) | ForEach-Object { [void]$cmbPublishers.Items.Add($_) }
    Update-Log "System scan complete. Found $($global:allAppsRaw.Count) applications."
    $btnRefreshAll.IsEnabled = $true
}

Function Execute-Uninstall {
    param($apps)
    if (!$apps -or $apps.Count -eq 0) { [System.Windows.MessageBox]::Show("No apps selected."); return }
    if ([System.Windows.MessageBox]::Show("Uninstall $($apps.Count) items sequentially?", "Confirm", "YesNo", "Warning") -ne "Yes") { return }

    foreach ($app in $apps) {
        Update-Log "Removing: $($app.DisplayName)..."
        $cmd = if ($app.QuietUninstallString) { $app.QuietUninstallString } else { $app.UninstallString }
        if ($cmd -match "msiexec") {
            $cmd = $cmd -replace "/[iI]", "/x"
            if ($cmd -notmatch "/qn") { $cmd += " /qn /norestart REBOOT=ReallySuppress" }
        } elseif ($cmd -match "unins.*\.exe") { $cmd += " /VERYSILENT /SUPPRESSMSGBOXES /NORESTART" }
        try {
            Update-Log " > Command: $cmd"
            $p = Start-Process "cmd.exe" -ArgumentList "/c `"$cmd`"" -WindowStyle Hidden -Wait -PassThru
            Update-Log " > Result: Code $($p.ExitCode)"
        } catch { Update-Log " > Error: $($_.Exception.Message)" }
    }
    Refresh-AppList
}

$dgAllApps.Add_PreviewMouseDown({
    param($sender, $e)
    $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($e.OriginalSource)
    while ($null -ne $dep -and $dep.GetType().Name -ne "DataGridCell") { $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep) }
    if ($null -ne $dep -and $dep.Column.Header -eq "Select") {
        $clickedItem = $dep.DataContext
        if ($null -ne $clickedItem) {
            $selectedItems = $dgAllApps.SelectedItems
            $newState = -not $clickedItem.IsSelected
            if ($selectedItems.Count -gt 1 -and $selectedItems.Contains($clickedItem)) {
                foreach ($item in $selectedItems) { $item.IsSelected = $newState }
            } else { $clickedItem.IsSelected = $newState }
            $dgAllApps.Items.Refresh(); $e.Handled = $true
        }
    }
})

$menuExit.Add_Click({ $window.Close() })
$menuGuide.Add_Click({ Show-UserGuide })
$menuChangelog.Add_Click({ Show-Changelog })
$menuAbout.Add_Click({ Show-About })
$txtFilterAllName.Add_TextChanged({ Apply-AllAppsFilter })
$txtFilterAllPublisher.Add_TextChanged({ Apply-AllAppsFilter })
$btnClearFilters.Add_Click({ $txtFilterAllName.Text = ""; $txtFilterAllPublisher.Text = ""; Apply-AllAppsFilter })
$btnRefreshAll.Add_Click({ Refresh-AppList })
$window.Add_Loaded({ Refresh-AppList })
$btnUninstallSelected.Add_Click({ Execute-Uninstall @($global:allAppsRaw | Where-Object { $_.IsSelected }) })
$cmbPublishers.Add_SelectionChanged({ if ($cmbPublishers.SelectedItem) { $dgPublisherApps.ItemsSource = [System.Collections.ArrayList]@($global:allAppsRaw | Where-Object { $_.Publisher -eq $cmbPublishers.SelectedItem }) } })
$btnSearchName.Add_Click({ if ($txtSearchName.Text) { $dgNameApps.ItemsSource = [System.Collections.ArrayList]@($global:allAppsRaw | Where-Object { $_.DisplayName -like "*$($txtSearchName.Text)*" }) } })
$btnSearchVendor.Add_Click({ if ($txtSearchVendor.Text) { $dgVendorApps.ItemsSource = [System.Collections.ArrayList]@($global:allAppsRaw | Where-Object { $_.Publisher -like "*$($txtSearchVendor.Text)*" }) } })
$btnUninstallPublisher.Add_Click({ Execute-Uninstall $dgPublisherApps.ItemsSource })
$btnUninstallName.Add_Click({ Execute-Uninstall $dgNameApps.ItemsSource })
$btnUninstallVendor.Add_Click({ Execute-Uninstall $dgVendorApps.ItemsSource })

$window.Add_KeyDown({
    param($sender, $e)
    if ([System.Windows.Input.Keyboard]::Modifiers -eq "Control") {
        switch ($e.Key) {
            "D1" { $mainTabs.SelectedIndex = 0; $e.Handled = $true }
            "D2" { $mainTabs.SelectedIndex = 1; $e.Handled = $true }
            "D3" { $mainTabs.SelectedIndex = 2; $e.Handled = $true }
            "D4" { $mainTabs.SelectedIndex = 3; $e.Handled = $true }
        }
    }
})

[void]$window.ShowDialog()