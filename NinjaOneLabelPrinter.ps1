#Requires -Version 5.1
# ============================================================
# NinjaOne Asset Label Printer
# ============================================================
# Konfigurationsdatei: %APPDATA%\NinjaOneLabelPrinter\config.json
# ============================================================

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# --- Konfigurationsverwaltung ---
$configDir  = Join-Path $env:APPDATA "NinjaOneLabelPrinter"
$configFile = Join-Path $configDir "config.json"

function Get-AppConfig {
    if (Test-Path $configFile) {
        return Get-Content $configFile -Raw | ConvertFrom-Json
    }
    return [PSCustomObject]@{
        NinjaBaseUrl   = "https://eu.ninjarmm.com"   # oder app.ninjarmm.com
        ClientId       = ""
        ClientSecret   = ""
        LastPrinter    = ""
        LabelWidthCm  = 4.0
        LabelHeightCm = 2.5
        LogoPath       = ""
    }
}

function Save-AppConfig($cfg) {
    if (!(Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    $cfg | ConvertTo-Json -Depth 5 | Set-Content $configFile -Encoding UTF8
}

$script:Config = Get-AppConfig

# --- NinjaOne API Helfer ---
$script:AccessToken = $null

function Connect-NinjaOne {
    param($BaseUrl, $ClientId, $ClientSecret)
    $tokenUrl = "$BaseUrl/oauth/token"
    $body = @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "monitoring management"
    }
    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        $script:AccessToken = $response.access_token
        return $true
    } catch {
        [System.Windows.MessageBox]::Show("Verbindung fehlgeschlagen:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
        return $false
    }
}

function Invoke-NinjaApi {
    param([string]$Endpoint)
    $headers = @{ Authorization = "Bearer $($script:AccessToken)" }
    $url = "$($script:Config.NinjaBaseUrl)/api/v2$Endpoint"
    return Invoke-RestMethod -Uri $url -Headers $headers -Method Get
}

function Get-NinjaOrganizations {
    return Invoke-NinjaApi -Endpoint "/organizations"
}

function Get-NinjaDevicesByOrg {
    param([int]$OrgId)
    return Invoke-NinjaApi -Endpoint "/organization/$OrgId/devices"
}

function Get-NinjaAllDevicesDetailed {
    return Invoke-NinjaApi -Endpoint "/devices-detailed"
}

# --- XAML UI Definition ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NinjaOne Asset Label Printer" Height="750" Width="1100"
        WindowStartupLocation="CenterScreen" Background="#1e1e2e">
    <Window.Resources>
        <Style x:Key="HeaderText" TargetType="TextBlock">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="0,0,0,4"/>
        </Style>
        <Style x:Key="InputBox" TargetType="TextBox">
            <Setter Property="Background" Value="#2a2a3d"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#444466"/>
            <Setter Property="Padding" Value="4,3"/>
            <Setter Property="FontSize" Value="12"/>
        </Style>
        <Style x:Key="ActionButton" TargetType="Button">
            <Setter Property="Background" Value="#5865f2"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="14,6"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="260"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="320"/>
        </Grid.ColumnDefinitions>

        <!-- LINKE SPALTE: Organisationen & Geräte -->
        <Border Grid.Column="0" Background="#252540" CornerRadius="0" Margin="0">
            <DockPanel Margin="10">
                <StackPanel DockPanel.Dock="Top">
                    <TextBlock Text="⚙ Verbindung" Style="{StaticResource HeaderText}" Margin="0,0,0,6"/>
                    <Button Name="btnConnect" Content="Mit NinjaOne verbinden" Style="{StaticResource ActionButton}" Margin="0,0,0,10"/>
                    <Separator Background="#444466" Margin="0,0,0,10"/>
                    <TextBlock Text="🏢 Organisationen" Style="{StaticResource HeaderText}"/>
                </StackPanel>
                <TreeView Name="tvOrganizations" Background="#2a2a3d" Foreground="White"
                          BorderBrush="#444466" FontSize="12" Margin="0,4,0,0"/>
            </DockPanel>
        </Border>

        <!-- MITTLERE SPALTE: Geräteliste + Zuletzt hinzugefügt -->
        <Grid Grid.Column="1" Margin="10">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="180"/>
            </Grid.RowDefinitions>

            <TextBlock Grid.Row="0" Text="💻 Geräte der Organisation" Style="{StaticResource HeaderText}"/>
            <DataGrid Name="dgDevices" Grid.Row="1" AutoGenerateColumns="False"
                      Background="#2a2a3d" Foreground="White" RowBackground="#2a2a3d"
                      AlternatingRowBackground="#303050" BorderBrush="#444466"
                      GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="#3a3a55"
                      CanUserAddRows="False" IsReadOnly="True" SelectionMode="Extended"
                      FontSize="12" HeadersVisibility="Column">
                <DataGrid.ColumnHeaderStyle>
                    <Style TargetType="DataGridColumnHeader">
                        <Setter Property="Background" Value="#383860"/>
                        <Setter Property="Foreground" Value="White"/>
                        <Setter Property="Padding" Value="6,4"/>
                        <Setter Property="FontWeight" Value="SemiBold"/>
                    </Style>
                </DataGrid.ColumnHeaderStyle>
                <DataGrid.Columns>
                    <DataGridTextColumn Header="Gerätename" Binding="{Binding SystemName}" Width="*"/>
                    <DataGridTextColumn Header="Typ" Binding="{Binding NodeClass}" Width="80"/>
                    <DataGridTextColumn Header="OS" Binding="{Binding OS}" Width="120"/>
                    <DataGridTextColumn Header="Erstellt" Binding="{Binding CreateTime}" Width="100"/>
                </DataGrid.Columns>
            </DataGrid>

            <TextBlock Grid.Row="2" Text="🕐 Zuletzt hinzugefügte Geräte" Style="{StaticResource HeaderText}" Margin="0,10,0,0"/>
            <DataGrid Name="dgRecent" Grid.Row="3" AutoGenerateColumns="False"
                      Background="#2a2a3d" Foreground="#90ee90" RowBackground="#2a2a3d"
                      AlternatingRowBackground="#303050" BorderBrush="#444466"
                      GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="#3a3a55"
                      CanUserAddRows="False" IsReadOnly="True" SelectionMode="Extended"
                      FontSize="12" HeadersVisibility="Column">
                <DataGrid.ColumnHeaderStyle>
                    <Style TargetType="DataGridColumnHeader">
                        <Setter Property="Background" Value="#2e4e2e"/>
                        <Setter Property="Foreground" Value="White"/>
                        <Setter Property="Padding" Value="6,4"/>
                        <Setter Property="FontWeight" Value="SemiBold"/>
                    </Style>
                </DataGrid.ColumnHeaderStyle>
                <DataGrid.Columns>
                    <DataGridTextColumn Header="Gerätename" Binding="{Binding SystemName}" Width="*"/>
                    <DataGridTextColumn Header="Organisation" Binding="{Binding OrgName}" Width="120"/>
                    <DataGridTextColumn Header="Hinzugefügt" Binding="{Binding CreateTime}" Width="100"/>
                </DataGrid.Columns>
            </DataGrid>
        </Grid>

        <!-- RECHTE SPALTE: Etiketten-Einstellungen & Vorschau -->
        <Border Grid.Column="2" Background="#252540" CornerRadius="0">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel Margin="12">
                    <TextBlock Text="🏷 Etiketten-Designer" FontSize="15" FontWeight="Bold"
                               Foreground="#5865f2" Margin="0,0,0,12"/>

                    <!-- Organisationsname Override -->
                    <TextBlock Text="Organisationsname (überschreibbar):" Style="{StaticResource HeaderText}"/>
                    <TextBox Name="txtOrgName" Style="{StaticResource InputBox}" Margin="0,0,0,8"/>

                    <!-- Datum Override -->
                    <TextBlock Text="Datum (Monat/Jahr, überschreibbar):" Style="{StaticResource HeaderText}"/>
                    <TextBox Name="txtDate" Style="{StaticResource InputBox}" Margin="0,0,0,8"/>

                    <!-- Etikettenmaße -->
                    <TextBlock Text="Etikettengröße:" Style="{StaticResource HeaderText}"/>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                        <TextBox Name="txtLabelWidth" Style="{StaticResource InputBox}" Width="60" Text="4,0"/>
                        <TextBlock Text=" x " Foreground="White" VerticalAlignment="Center" FontSize="12"/>
                        <TextBox Name="txtLabelHeight" Style="{StaticResource InputBox}" Width="60" Text="2,5"/>
                        <TextBlock Text=" cm" Foreground="White" VerticalAlignment="Center" FontSize="12"/>
                    </StackPanel>

                    <!-- Logo -->
                    <TextBlock Text="Logo:" Style="{StaticResource HeaderText}"/>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                        <TextBox Name="txtLogoPath" Style="{StaticResource InputBox}" Width="190" IsReadOnly="True"/>
                        <Button Name="btnSelectLogo" Content="📂" Style="{StaticResource ActionButton}"
                                Margin="4,0,0,0" Padding="8,4"/>
                    </StackPanel>

                    <!-- Drucker -->
                    <TextBlock Text="Drucker:" Style="{StaticResource HeaderText}"/>
                    <ComboBox Name="cbPrinter" Background="#2a2a3d" Foreground="Black"
                              FontSize="12" Margin="0,0,0,8"/>

                    <Separator Background="#444466" Margin="0,8"/>

                    <!-- Vorschau -->
                    <TextBlock Text="Vorschau:" Style="{StaticResource HeaderText}" Margin="0,4,0,4"/>
                    <Border Name="borderPreview" Background="White" BorderBrush="#888"
                            BorderThickness="1" HorizontalAlignment="Center"
                            Margin="0,0,0,12" Padding="0">
                        <Canvas Name="canvasPreview" Width="280" Height="175"/>
                    </Border>

                    <!-- Buttons -->
                    <Button Name="btnPreview" Content="🔄 Vorschau aktualisieren"
                            Style="{StaticResource ActionButton}" Margin="0,0,0,6"/>
                    <Button Name="btnPrint" Content="🖨 Etikett(en) drucken"
                            Style="{StaticResource ActionButton}" Background="#2ea043"/>
                    <Button Name="btnSettings" Content="💾 Einstellungen speichern"
                            Style="{StaticResource ActionButton}" Background="#666680" Margin="0,6,0,0"/>
                </StackPanel>
            </ScrollViewer>
        </Border>
    </Grid>
</Window>
"@

# --- Fenster laden ---
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Steuerelemente referenzieren
$btnConnect       = $window.FindName("btnConnect")
$tvOrganizations  = $window.FindName("tvOrganizations")
$dgDevices        = $window.FindName("dgDevices")
$dgRecent         = $window.FindName("dgRecent")
$txtOrgName       = $window.FindName("txtOrgName")
$txtDate          = $window.FindName("txtDate")
$txtLabelWidth    = $window.FindName("txtLabelWidth")
$txtLabelHeight   = $window.FindName("txtLabelHeight")
$txtLogoPath      = $window.FindName("txtLogoPath")
$btnSelectLogo    = $window.FindName("btnSelectLogo")
$cbPrinter        = $window.FindName("cbPrinter")
$canvasPreview    = $window.FindName("canvasPreview")
$btnPreview       = $window.FindName("btnPreview")
$btnPrint         = $window.FindName("btnPrint")
$btnSettings      = $window.FindName("btnSettings")

# --- Initialisierung ---
$txtDate.Text = (Get-Date).ToString("MM/yyyy")
$txtLabelWidth.Text  = $script:Config.LabelWidthCm.ToString()
$txtLabelHeight.Text = $script:Config.LabelHeightCm.ToString()
$txtLogoPath.Text    = $script:Config.LogoPath

# Drucker laden
$printers = (Get-Printer | Where-Object { $_.Type -eq "Local" -or $_.Type -eq "Connection" }).Name
foreach ($p in $printers) { $cbPrinter.Items.Add($p) | Out-Null }
if ($script:Config.LastPrinter -and $cbPrinter.Items.Contains($script:Config.LastPrinter)) {
    $cbPrinter.SelectedItem = $script:Config.LastPrinter
} elseif ($cbPrinter.Items.Count -gt 0) {
    $cbPrinter.SelectedIndex = 0
}

# --- Globale Daten ---
$script:Organizations = @()
$script:AllDevices    = @()
$script:OrgLookup     = @{}

# --- Verbindung herstellen ---
$btnConnect.Add_Click({
    # Einfacher Settings-Dialog wenn noch keine Credentials da sind
    if (-not $script:Config.ClientId -or -not $script:Config.ClientSecret) {
        $settingsXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="NinjaOne API Einstellungen" Height="280" Width="420"
        WindowStartupLocation="CenterOwner" Background="#1e1e2e">
    <StackPanel Margin="16">
        <TextBlock Text="Base URL:" Foreground="White" FontSize="12"/>
        <TextBox Name="sBaseUrl" Background="#2a2a3d" Foreground="White" Padding="4" Margin="0,2,0,8"/>
        <TextBlock Text="Client ID:" Foreground="White" FontSize="12"/>
        <TextBox Name="sClientId" Background="#2a2a3d" Foreground="White" Padding="4" Margin="0,2,0,8"/>
        <TextBlock Text="Client Secret:" Foreground="White" FontSize="12"/>
        <PasswordBox Name="sClientSecret" Background="#2a2a3d" Foreground="White" Padding="4" Margin="0,2,0,8"/>
        <Button Name="sSave" Content="Verbinden" Background="#5865f2" Foreground="White"
                FontSize="12" Padding="10,5" HorizontalAlignment="Right" Margin="0,8,0,0"/>
    </StackPanel>
</Window>
"@
        $sr = New-Object System.Xml.XmlNodeReader ([xml]$settingsXaml)
        $sw = [Windows.Markup.XamlReader]::Load($sr)
        $sw.FindName("sBaseUrl").Text = $script:Config.NinjaBaseUrl
        $sw.FindName("sClientId").Text = $script:Config.ClientId
        $sw.FindName("sClientSecret").Password = $script:Config.ClientSecret
        $sw.FindName("sSave").Add_Click({
            $script:Config.NinjaBaseUrl  = $sw.FindName("sBaseUrl").Text
            $script:Config.ClientId      = $sw.FindName("sClientId").Text
            $script:Config.ClientSecret  = $sw.FindName("sClientSecret").Password
            Save-AppConfig $script:Config
            $sw.DialogResult = $true
            $sw.Close()
        })
        $sw.Owner = $window
        if (-not $sw.ShowDialog()) { return }
    }

    # Token holen
    $ok = Connect-NinjaOne -BaseUrl $script:Config.NinjaBaseUrl `
                           -ClientId $script:Config.ClientId `
                           -ClientSecret $script:Config.ClientSecret
    if (-not $ok) { return }

    # Organisationen laden
    $script:Organizations = @(Get-NinjaOrganizations)
    $script:OrgLookup = @{}
    foreach ($org in $script:Organizations) { $script:OrgLookup[$org.id] = $org.name }

    # TreeView befüllen
    $tvOrganizations.Items.Clear()
    foreach ($org in ($script:Organizations | Sort-Object name)) {
        $item = New-Object System.Windows.Controls.TreeViewItem
        $item.Header = $org.name
        $item.Tag    = $org.id
        $item.Foreground = [System.Windows.Media.Brushes]::White
        $tvOrganizations.Items.Add($item) | Out-Null
    }

    # Alle Geräte für "Zuletzt hinzugefügt" laden
    try {
        $script:AllDevices = @(Get-NinjaAllDevicesDetailed)
        $recentDevices = $script:AllDevices |
            Sort-Object { if ($_.createTime) { [DateTimeOffset]::FromUnixTimeSeconds($_.createTime).DateTime } else { [DateTime]::MinValue } } -Descending |
            Select-Object -First 20 |
            ForEach-Object {
                [PSCustomObject]@{
                    SystemName = $_.systemName
                    OrgName    = if ($script:OrgLookup.ContainsKey($_.organizationId)) { $script:OrgLookup[$_.organizationId] } else { "?" }
                    CreateTime = if ($_.createTime) { [DateTimeOffset]::FromUnixTimeSeconds($_.createTime).DateTime.ToString("dd.MM.yyyy") } else { "-" }
                    RawDevice  = $_
                }
            }
        $dgRecent.ItemsSource = $recentDevices
    } catch {
        # Fallback: Zuletzt-Liste leer lassen
    }

    [System.Windows.MessageBox]::Show("Verbunden! $($script:Organizations.Count) Organisationen geladen.", "Erfolg", "OK", "Information")
})

# --- Organisation auswählen → Geräte laden ---
$tvOrganizations.Add_SelectedItemChanged({
    $selected = $tvOrganizations.SelectedItem
    if (-not $selected -or -not $selected.Tag) { return }

    $orgId   = $selected.Tag
    $orgName = $selected.Header.ToString()
    $txtOrgName.Text = $orgName
    $txtDate.Text = (Get-Date).ToString("MM/yyyy")

    try {
        $devices = @(Get-NinjaDevicesByOrg -OrgId $orgId)
        $deviceList = $devices | ForEach-Object {
            [PSCustomObject]@{
                SystemName = $_.systemName
                NodeClass  = $_.nodeClass
                OS         = if ($_.os) { $_.os.name } else { "-" }
                CreateTime = if ($_.createTime) { [DateTimeOffset]::FromUnixTimeSeconds($_.createTime).DateTime.ToString("dd.MM.yyyy") } else { "-" }
                RawDevice  = $_
            }
        }
        $dgDevices.ItemsSource = $deviceList
    } catch {
        [System.Windows.MessageBox]::Show("Fehler beim Laden der Geräte:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
})

# --- Logo auswählen ---
$btnSelectLogo.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = "Bilder|*.png;*.jpg;*.jpeg;*.bmp;*.gif|Alle Dateien|*.*"
    $dlg.Title  = "Logo auswählen"
    if ($dlg.ShowDialog()) {
        $txtLogoPath.Text = $dlg.FileName
        $script:Config.LogoPath = $dlg.FileName
    }
})

# --- Vorschau zeichnen ---
function Update-LabelPreview {
    $canvasPreview.Children.Clear()

    $canvasW = $canvasPreview.Width    # 280
    $canvasH = $canvasPreview.Height   # 175

    # Hintergrund weiß
    $bg = New-Object System.Windows.Shapes.Rectangle
    $bg.Width  = $canvasW
    $bg.Height = $canvasH
    $bg.Fill   = [System.Windows.Media.Brushes]::White
    [System.Windows.Controls.Canvas]::SetLeft($bg, 0)
    [System.Windows.Controls.Canvas]::SetTop($bg, 0)
    $canvasPreview.Children.Add($bg) | Out-Null

    # Rahmen
    $border = New-Object System.Windows.Shapes.Rectangle
    $border.Width  = $canvasW
    $border.Height = $canvasH
    $border.Stroke = [System.Windows.Media.Brushes]::Black
    $border.StrokeThickness = 2
    [System.Windows.Controls.Canvas]::SetLeft($border, 0)
    [System.Windows.Controls.Canvas]::SetTop($border, 0)
    $canvasPreview.Children.Add($border) | Out-Null

    # Oberer Balken (dicker) mit Organisationsname
    $headerH = 30
    $header = New-Object System.Windows.Shapes.Rectangle
    $header.Width  = $canvasW
    $header.Height = $headerH
    $header.Fill   = [System.Windows.Media.Brushes]::Black
    [System.Windows.Controls.Canvas]::SetLeft($header, 0)
    [System.Windows.Controls.Canvas]::SetTop($header, 0)
    $canvasPreview.Children.Add($header) | Out-Null

    $orgText = New-Object System.Windows.Controls.TextBlock
    $orgText.Text       = $txtOrgName.Text
    $orgText.Foreground = [System.Windows.Media.Brushes]::White
    $orgText.FontSize   = 13
    $orgText.FontWeight = [System.Windows.FontWeights]::Bold
    $orgText.Width      = $canvasW - 10
    $orgText.TextAlignment = [System.Windows.TextAlignment]::Center
    [System.Windows.Controls.Canvas]::SetLeft($orgText, 5)
    [System.Windows.Controls.Canvas]::SetTop($orgText, 5)
    $canvasPreview.Children.Add($orgText) | Out-Null

    # Gerätename in der Mitte
    $selectedDevices = @()
    if ($dgDevices.SelectedItems.Count -gt 0) {
        $selectedDevices = $dgDevices.SelectedItems
    } elseif ($dgRecent.SelectedItems.Count -gt 0) {
        $selectedDevices = $dgRecent.SelectedItems
    }
    $deviceName = if ($selectedDevices.Count -gt 0) { $selectedDevices[0].SystemName } else { "GERÄTENAME" }

    $deviceText = New-Object System.Windows.Controls.TextBlock
    $deviceText.Text       = $deviceName
    $deviceText.Foreground = [System.Windows.Media.Brushes]::Black
    $deviceText.FontSize   = 16
    $deviceText.FontWeight = [System.Windows.FontWeights]::Bold
    $deviceText.Width      = $canvasW - 20
    $deviceText.TextAlignment = [System.Windows.TextAlignment]::Center
    [System.Windows.Controls.Canvas]::SetLeft($deviceText, 10)
    [System.Windows.Controls.Canvas]::SetTop($deviceText, ($canvasH / 2) - 15)
    $canvasPreview.Children.Add($deviceText) | Out-Null

    # Datum links unten
    $dateText = New-Object System.Windows.Controls.TextBlock
    $dateText.Text       = $txtDate.Text
    $dateText.Foreground = [System.Windows.Media.Brushes]::DarkGray
    $dateText.FontSize   = 10
    [System.Windows.Controls.Canvas]::SetLeft($dateText, 8)
    [System.Windows.Controls.Canvas]::SetTop($dateText, $canvasH - 22)
    $canvasPreview.Children.Add($dateText) | Out-Null

    # Logo rechts unten
    if ($txtLogoPath.Text -and (Test-Path $txtLogoPath.Text)) {
        try {
            $bitmapImage = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmapImage.BeginInit()
            $bitmapImage.UriSource = New-Object System.Uri($txtLogoPath.Text)
            $bitmapImage.DecodePixelHeight = 30
            $bitmapImage.EndInit()

            $img = New-Object System.Windows.Controls.Image
            $img.Source = $bitmapImage
            $img.Height = 30
            $img.Width  = 50
            [System.Windows.Controls.Canvas]::SetLeft($img, $canvasW - 60)
            [System.Windows.Controls.Canvas]::SetTop($img, $canvasH - 38)
            $canvasPreview.Children.Add($img) | Out-Null
        } catch { }
    }

    # Größenangabe
    $sizeText = New-Object System.Windows.Controls.TextBlock
    $sizeText.Text       = "$($txtLabelWidth.Text) x $($txtLabelHeight.Text) cm"
    $sizeText.Foreground = [System.Windows.Media.Brushes]::LightGray
    $sizeText.FontSize   = 8
    $sizeText.FontStyle  = [System.Windows.FontStyles]::Italic
    [System.Windows.Controls.Canvas]::SetLeft($sizeText, $canvasW - 80)
    [System.Windows.Controls.Canvas]::SetTop($sizeText, $canvasH - 14)
    $canvasPreview.Children.Add($sizeText) | Out-Null
}

$btnPreview.Add_Click({ Update-LabelPreview })
$dgDevices.Add_SelectionChanged({ Update-LabelPreview })
$dgRecent.Add_SelectionChanged({
    # Beim Klick auf "Zuletzt hinzugefügt" → OrgName übernehmen
    if ($dgRecent.SelectedItem) {
        $txtOrgName.Text = $dgRecent.SelectedItem.OrgName
    }
    Update-LabelPreview
})

# --- Drucken ---
$btnPrint.Add_Click({
    $selectedPrinter = $cbPrinter.SelectedItem
    if (-not $selectedPrinter) {
        [System.Windows.MessageBox]::Show("Bitte Drucker auswählen!", "Hinweis", "OK", "Warning")
        return
    }

    # Geräte sammeln (aus beiden DataGrids)
    $devicesToPrint = @()
    if ($dgDevices.SelectedItems.Count -gt 0) {
        $devicesToPrint += $dgDevices.SelectedItems | ForEach-Object { $_.SystemName }
    }
    if ($dgRecent.SelectedItems.Count -gt 0) {
        $devicesToPrint += $dgRecent.SelectedItems | ForEach-Object { $_.SystemName }
    }

    if ($devicesToPrint.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Bitte mindestens ein Gerät auswählen!", "Hinweis", "OK", "Warning")
        return
    }

    # Drucker merken
    $script:Config.LastPrinter = $selectedPrinter
    Save-AppConfig $script:Config

    # Druckmaße berechnen (cm → 1/100 Zoll, 1cm = 0.3937 Zoll)
    $labelWcm = [double]::Parse($txtLabelWidth.Text.Replace(",", "."),  [System.Globalization.CultureInfo]::InvariantCulture)
    $labelHcm = [double]::Parse($txtLabelHeight.Text.Replace(",", "."), [System.Globalization.CultureInfo]::InvariantCulture)
    $labelW100 = [int]($labelWcm * 0.3937 * 100)
    $labelH100 = [int]($labelHcm * 0.3937 * 100)

    foreach ($devName in $devicesToPrint) {
        $printDoc = New-Object System.Drawing.Printing.PrintDocument
        $printDoc.PrinterSettings.PrinterName = $selectedPrinter
        $printDoc.DefaultPageSettings.PaperSize = New-Object System.Drawing.Printing.PaperSize("Label", $labelW100, $labelH100)
        $printDoc.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(0, 0, 0, 0)

        $currentDevName = $devName
        $currentOrgName = $txtOrgName.Text
        $currentDate    = $txtDate.Text
        $currentLogo    = $txtLogoPath.Text

        $printDoc.Add_PrintPage({
            param($sender, $e)
            $g = $e.Graphics
            $w = $e.PageBounds.Width
            $h = $e.PageBounds.Height

            # Rahmen
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Black, 1)
            $g.DrawRectangle($pen, 1, 1, $w - 3, $h - 3)

            # Oberer Balken
            $headerH = [int]($h * 0.22)
            $g.FillRectangle([System.Drawing.Brushes]::Black, 0, 0, $w, $headerH)

            # Org-Name im Balken
            $orgFont = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(7, $headerH * 0.45), [System.Drawing.FontStyle]::Bold)
            $orgSize = $g.MeasureString($currentOrgName, $orgFont)
            $g.DrawString($currentOrgName, $orgFont, [System.Drawing.Brushes]::White,
                [int](($w - $orgSize.Width) / 2), [int](($headerH - $orgSize.Height) / 2))

            # Gerätename mittig
            $devFont = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(8, $h * 0.12), [System.Drawing.FontStyle]::Bold)
            $devSize = $g.MeasureString($currentDevName, $devFont)
            $g.DrawString($currentDevName, $devFont, [System.Drawing.Brushes]::Black,
                [int](($w - $devSize.Width) / 2), [int](($h - $devSize.Height) / 2))

            # Datum links unten
            $dateFont = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(5, $h * 0.08))
            $g.DrawString($currentDate, $dateFont, [System.Drawing.Brushes]::DimGray, 6, $h - 18)

            # Logo rechts unten
            if ($currentLogo -and (Test-Path $currentLogo)) {
                try {
                    $logo = [System.Drawing.Image]::FromFile($currentLogo)
                    $logoH = [int]($h * 0.22)
                    $logoW = [int]($logoH * ($logo.Width / $logo.Height))
                    $g.DrawImage($logo, $w - $logoW - 6, $h - $logoH - 4, $logoW, $logoH)
                    $logo.Dispose()
                } catch { }
            }
        })

        try {
            $printDoc.Print()
        } catch {
            [System.Windows.MessageBox]::Show("Druckfehler: $($_.Exception.Message)", "Fehler", "OK", "Error")
            return
        }
    }

    [System.Windows.MessageBox]::Show("$($devicesToPrint.Count) Etikett(en) gedruckt!", "Fertig", "OK", "Information")
})

# --- Einstellungen speichern ---
$btnSettings.Add_Click({
    $script:Config.LabelWidthCm  = [double]::Parse($txtLabelWidth.Text.Replace(",", "."),  [System.Globalization.CultureInfo]::InvariantCulture)
    $script:Config.LabelHeightCm = [double]::Parse($txtLabelHeight.Text.Replace(",", "."), [System.Globalization.CultureInfo]::InvariantCulture)
    $script:Config.LogoPath      = $txtLogoPath.Text
    $script:Config.LastPrinter   = $cbPrinter.SelectedItem
    Save-AppConfig $script:Config
    [System.Windows.MessageBox]::Show("Einstellungen gespeichert!", "OK", "OK", "Information")
})

# --- Initiale Vorschau ---
Update-LabelPreview

# --- Fenster anzeigen ---
$window.ShowDialog() | Out-Null