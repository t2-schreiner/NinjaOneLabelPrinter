#Requires -Version 7
# ============================================================
# NinjaOne Asset Label Printer
# ============================================================
# Configuration file: %APPDATA%\NinjaOneLabelPrinter\config.json
# ============================================================

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# --- Cryptography functions (AES-256 + PBKDF2) ---

function Protect-String {
    param([string]$PlainText, [string]$MasterPassword)
    $salt = New-Object byte[] 32
    $iv   = New-Object byte[] 16
    $rng  = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    $rng.GetBytes($salt); $rng.GetBytes($iv); $rng.Dispose()

    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $MasterPassword, $salt, 100000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $key = $kdf.GetBytes(32); $kdf.Dispose()

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key; $aes.IV = $iv
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $enc = $aes.CreateEncryptor()
    $plain = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $cipher = $enc.TransformFinalBlock($plain, 0, $plain.Length)
    $enc.Dispose(); $aes.Dispose()

    $combined = New-Object byte[] (32 + 16 + $cipher.Length)
    [Array]::Copy($salt, 0, $combined, 0, 32)
    [Array]::Copy($iv,   0, $combined, 32, 16)
    [Array]::Copy($cipher, 0, $combined, 48, $cipher.Length)

    [Array]::Clear($key, 0, $key.Length)
    [Array]::Clear($plain, 0, $plain.Length)
    return [Convert]::ToBase64String($combined)
}

function Unprotect-String {
    param([string]$CipherText, [string]$MasterPassword)
    $combined = [Convert]::FromBase64String($CipherText)

    $salt   = New-Object byte[] 32
    $iv     = New-Object byte[] 16
    $cipher = New-Object byte[] ($combined.Length - 48)
    [Array]::Copy($combined, 0,  $salt,   0, 32)
    [Array]::Copy($combined, 32, $iv,     0, 16)
    [Array]::Copy($combined, 48, $cipher, 0, $cipher.Length)

    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $MasterPassword, $salt, 100000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $key = $kdf.GetBytes(32); $kdf.Dispose()

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key; $aes.IV = $iv
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $dec = $aes.CreateDecryptor()
    $plain = $dec.TransformFinalBlock($cipher, 0, $cipher.Length)
    $dec.Dispose(); $aes.Dispose()

    $result = [System.Text.Encoding]::UTF8.GetString($plain)
    [Array]::Clear($key, 0, $key.Length)
    [Array]::Clear($plain, 0, $plain.Length)
    return $result
}

function New-MasterPasswordVerifier {
    param([string]$MasterPassword)
    $salt = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    $rng.GetBytes($salt); $rng.Dispose()
    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $MasterPassword, $salt, 100000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $hash = $kdf.GetBytes(32); $kdf.Dispose()
    $combined = New-Object byte[] 64
    [Array]::Copy($salt, 0, $combined, 0, 32)
    [Array]::Copy($hash, 0, $combined, 32, 32)
    [Array]::Clear($hash, 0, $hash.Length)
    return [Convert]::ToBase64String($combined)
}

function Test-MasterPassword {
    param([string]$MasterPassword, [string]$Verifier)
    $combined   = [Convert]::FromBase64String($Verifier)
    $salt       = New-Object byte[] 32
    $storedHash = New-Object byte[] 32
    [Array]::Copy($combined, 0,  $salt,       0, 32)
    [Array]::Copy($combined, 32, $storedHash, 0, 32)
    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $MasterPassword, $salt, 100000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $computed = $kdf.GetBytes(32); $kdf.Dispose()
    # Constant-time comparison
    $diff = 0
    for ($i = 0; $i -lt 32; $i++) { $diff = $diff -bor ($storedHash[$i] -bxor $computed[$i]) }
    [Array]::Clear($computed, 0, $computed.Length)
    return ($diff -eq 0)
}

# --- Configuration management ---
$configDir  = Join-Path $env:APPDATA "NinjaOneLabelPrinter"
$configFile = Join-Path $configDir "config.json"

function Get-AppConfig {
    $defaults = [PSCustomObject]@{
        NinjaBaseUrl           = "https://eu.ninjarmm.com"
        ClientId               = ""
        ClientSecret           = ""
        LastPrinter            = ""
        LabelWidthCm           = 4.0
        LabelHeightCm          = 2.5
        PaddingMm              = 0.0
        HeaderHeightPercent    = 22
        LogoHeightPercent      = 22
        LogoPath               = ""
        EncryptedClientId      = ""
        EncryptedClientSecret  = ""
        MasterPasswordVerifier = ""
        OrgNameOverrides       = @{}
    }
    if (Test-Path $configFile) {
        $raw = Get-Content $configFile -Raw | ConvertFrom-Json
        foreach ($prop in $raw.PSObject.Properties) {
            if ($defaults.PSObject.Properties[$prop.Name]) {
                $defaults.$($prop.Name) = $prop.Value
            }
        }
        # Convert OrgNameOverrides from PSCustomObject to hashtable
        if ($defaults.OrgNameOverrides -is [PSCustomObject]) {
            $ht = @{}
            foreach ($p in $defaults.OrgNameOverrides.PSObject.Properties) {
                $ht[$p.Name] = $p.Value
            }
            $defaults.OrgNameOverrides = $ht
        }
        # Legacy plaintext credentials: keep for migration prompt
        if ($raw.PSObject.Properties['ClientId'] -and $raw.ClientId -and
            (-not $raw.PSObject.Properties['EncryptedClientId'] -or -not $raw.EncryptedClientId)) {
            $defaults.ClientId     = $raw.ClientId
            $defaults.ClientSecret = $raw.ClientSecret
        }
    }
    return $defaults
}

function Save-AppConfig($cfg) {
    if (!(Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    # Build disk representation – sensitive fields are always encrypted, never plaintext
    $diskConfig = [ordered]@{
        NinjaBaseUrl           = $cfg.NinjaBaseUrl
        LastPrinter            = $cfg.LastPrinter
        LabelWidthCm           = $cfg.LabelWidthCm
        LabelHeightCm          = $cfg.LabelHeightCm
        PaddingMm              = $cfg.PaddingMm
        HeaderHeightPercent    = $cfg.HeaderHeightPercent
        LogoHeightPercent      = $cfg.LogoHeightPercent
        LogoPath               = $cfg.LogoPath
        OrgNameOverrides       = if ($cfg.OrgNameOverrides) { $cfg.OrgNameOverrides } else { @{} }
        EncryptedClientId      = ""
        EncryptedClientSecret  = ""
        MasterPasswordVerifier = ""
    }
    if ($script:MasterPassword) {
        if ($cfg.ClientId)     { $diskConfig.EncryptedClientId     = Protect-String -PlainText $cfg.ClientId     -MasterPassword $script:MasterPassword }
        if ($cfg.ClientSecret) { $diskConfig.EncryptedClientSecret = Protect-String -PlainText $cfg.ClientSecret -MasterPassword $script:MasterPassword }
        if ($script:MasterPasswordVerifier) {
            $diskConfig.MasterPasswordVerifier = $script:MasterPasswordVerifier
        } else {
            $script:MasterPasswordVerifier = New-MasterPasswordVerifier -MasterPassword $script:MasterPassword
            $diskConfig.MasterPasswordVerifier = $script:MasterPasswordVerifier
        }
    }
    [PSCustomObject]$diskConfig | ConvertTo-Json -Depth 5 | Set-Content $configFile -Encoding UTF8
}

$script:Config = Get-AppConfig
$script:MasterPassword         = $null
$script:MasterPasswordVerifier = $null

# --- NinjaOne API helpers ---
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
        [System.Windows.MessageBox]::Show("Connection failed:`n$($_.Exception.Message)", "Error", "OK", "Error")
        return $false
    }
}

function Invoke-NinjaApi {
    param([string]$Endpoint)
    $headers = @{ Authorization = "Bearer $($script:AccessToken)" }
    $url = "$($script:Config.NinjaBaseUrl)/api/v2$Endpoint"
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    # Paginated NinjaOne API responses wrap the actual data in a results/items array
    if ($null -ne $response -and $response -isnot [System.Array]) {
        if ($response.PSObject.Properties['results'] -and $null -ne $response.results) { return $response.results }
        if ($response.PSObject.Properties['items']   -and $null -ne $response.items)   { return $response.items }
    }
    return $response
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

function Get-DeviceDisplayName {
    param($Device)
    if ($Device.systemName)  { return [string]$Device.systemName }
    if ($Device.displayName) { return [string]$Device.displayName }
    if ($Device.dnsName)     { return [string]$Device.dnsName }
    return "Device-$($Device.id)"
}

function Get-SafeOsName {
    param($OsObject)
    try {
        $os = if ($OsObject -is [System.Array]) { $OsObject[0] } else { $OsObject }
        if ($null -eq $os) { return "-" }
        if ($os -is [string]) { return $os }
        if ($os.PSObject.Properties['name'] -and $os.name) { return [string]$os.name }
        return "-"
    } catch {
        return "-"
    }
}

# --- XAML UI Definition ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NinjaOne Asset Label Printer" Height="750" Width="1100"
        WindowStartupLocation="CenterScreen" WindowState="Maximized" Background="#1e1e2e">
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

        <!-- LEFT COLUMN: Organizations & Devices -->
        <Border Grid.Column="0" Background="#252540" CornerRadius="0" Margin="0">
            <DockPanel Margin="10">
                <StackPanel DockPanel.Dock="Top">
                    <TextBlock Text="⚙ Connection" Style="{StaticResource HeaderText}" Margin="0,0,0,6"/>
                    <Button Name="btnConnect" Content="Connect to NinjaOne" Style="{StaticResource ActionButton}" Margin="0,0,0,10"/>
                    <Separator Background="#444466" Margin="0,0,0,10"/>
                    <TextBlock Text="🏢 Organizations" Style="{StaticResource HeaderText}"/>
                </StackPanel>
                <TreeView Name="tvOrganizations" Background="#2a2a3d" Foreground="White"
                          BorderBrush="#444466" FontSize="12" Margin="0,4,0,0"/>
            </DockPanel>
        </Border>

        <!-- MIDDLE COLUMN: Device list + Recently added -->
        <Grid Grid.Column="1" Margin="10">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="180"/>
            </Grid.RowDefinitions>

            <TextBlock Grid.Row="0" Text="💻 Organization Devices" Style="{StaticResource HeaderText}"/>
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
                    <DataGridTextColumn Header="Device Name" Binding="{Binding SystemName}" Width="*"/>
                    <DataGridTextColumn Header="Type" Binding="{Binding NodeClass}" Width="80"/>
                    <DataGridTextColumn Header="Asset ID" Binding="{Binding AssetId}" Width="80"/>
                </DataGrid.Columns>
            </DataGrid>

            <TextBlock Grid.Row="2" Text="🕐 Recently Added Devices" Style="{StaticResource HeaderText}" Margin="0,10,0,0"/>
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
                    <DataGridTextColumn Header="Device Name" Binding="{Binding SystemName}" Width="*"/>
                    <DataGridTextColumn Header="Organisation" Binding="{Binding OrgName}" Width="120"/>
                    <DataGridTextColumn Header="Asset ID" Binding="{Binding AssetId}" Width="80"/>
                </DataGrid.Columns>
            </DataGrid>
        </Grid>

        <!-- RIGHT COLUMN: Label settings & preview -->
        <Border Grid.Column="2" Background="#252540" CornerRadius="0">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel Margin="12">
                    <TextBlock Text="🏷 Label Designer" FontSize="15" FontWeight="Bold"
                               Foreground="#5865f2" Margin="0,0,0,12"/>

                    <!-- Organization name override -->
                    <TextBlock Text="Organization name (editable):" Style="{StaticResource HeaderText}"/>
                    <TextBox Name="txtOrgName" Style="{StaticResource InputBox}" Margin="0,0,0,8"/>

                    <!-- Date override -->
                    <TextBlock Text="Date (month/year, editable):" Style="{StaticResource HeaderText}"/>
                    <TextBox Name="txtDate" Style="{StaticResource InputBox}" Margin="0,0,0,8"/>

                    <!-- Label dimensions -->
                    <TextBlock Text="Label size:" Style="{StaticResource HeaderText}"/>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                        <TextBox Name="txtLabelWidth" Style="{StaticResource InputBox}" Width="60" Text="4,0"/>
                        <TextBlock Text=" x " Foreground="White" VerticalAlignment="Center" FontSize="12"/>
                        <TextBox Name="txtLabelHeight" Style="{StaticResource InputBox}" Width="60" Text="2,5"/>
                        <TextBlock Text=" cm" Foreground="White" VerticalAlignment="Center" FontSize="12"/>
                    </StackPanel>

                    <!-- Inner padding -->
                    <TextBlock Text="Inner padding (mm, all sides):" Style="{StaticResource HeaderText}"/>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                        <TextBox Name="txtPaddingMm" Style="{StaticResource InputBox}" Width="60" Text="0"/>
                        <TextBlock Text=" mm" Foreground="White" VerticalAlignment="Center" FontSize="12"/>
                    </StackPanel>

                    <!-- Header / Logo height -->
                    <TextBlock Text="Header / Logo (% of label height):" Style="{StaticResource HeaderText}"/>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                        <TextBox Name="txtHeaderPercent" Style="{StaticResource InputBox}" Width="50" Text="22"/>
                        <TextBlock Text=" / " Foreground="White" VerticalAlignment="Center" FontSize="12"/>
                        <TextBox Name="txtLogoPercent" Style="{StaticResource InputBox}" Width="50" Text="22"/>
                        <TextBlock Text=" %" Foreground="White" VerticalAlignment="Center" FontSize="12"/>
                    </StackPanel>

                    <!-- Logo -->
                    <TextBlock Text="Logo:" Style="{StaticResource HeaderText}"/>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                        <TextBox Name="txtLogoPath" Style="{StaticResource InputBox}" Width="190" IsReadOnly="True"/>
                        <Button Name="btnSelectLogo" Content="📂" Style="{StaticResource ActionButton}"
                                Margin="4,0,0,0" Padding="8,4"/>
                    </StackPanel>

                    <!-- Printer -->
                    <TextBlock Text="Printer:" Style="{StaticResource HeaderText}"/>
                    <ComboBox Name="cbPrinter" Background="#2a2a3d" Foreground="Black"
                              FontSize="12" Margin="0,0,0,8"/>

                    <Separator Background="#444466" Margin="0,8"/>

                    <!-- Preview -->
                    <TextBlock Text="Preview:" Style="{StaticResource HeaderText}" Margin="0,4,0,4"/>
                    <Border Name="borderPreview" Background="#1e1e2e" BorderBrush="#888"
                            BorderThickness="1" HorizontalAlignment="Center"
                            Margin="0,0,0,12" Padding="0">
                        <Canvas Name="canvasPreview" Width="280" Height="175"
                                Background="#1e1e2e"/>
                    </Border>

                    <!-- Buttons -->
                    <Button Name="btnPrint" Content="🖨 Print label(s)"
                            Style="{StaticResource ActionButton}" Background="#2ea043"/>
                    <Button Name="btnSettings" Content="💾 Save settings"
                            Style="{StaticResource ActionButton}" Background="#666680" Margin="0,6,0,0"/>
                    <Button Name="btnChangePw" Content="🔑 Change master password"
                            Style="{StaticResource ActionButton}" Background="#666680" Margin="0,6,0,0"/>
                    <Button Name="btnReset" Content="🔄 Reset credentials"
                            Style="{StaticResource ActionButton}" Background="#cc3333" Margin="0,6,0,0"/>

                    <!-- Copyright footer -->
                    <Separator Background="#444466" Margin="0,12,0,8"/>
                    <TextBlock Text="© Thomas Schreiner, www.t2.at" Foreground="#888"
                               FontSize="10" HorizontalAlignment="Center"/>
                </StackPanel>
            </ScrollViewer>
        </Border>
    </Grid>
</Window>
"@

# --- Load window ---
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Reference controls
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
$txtPaddingMm     = $window.FindName("txtPaddingMm")
$txtHeaderPercent = $window.FindName("txtHeaderPercent")
$txtLogoPercent   = $window.FindName("txtLogoPercent")
$cbPrinter        = $window.FindName("cbPrinter")
$canvasPreview    = $window.FindName("canvasPreview")
$btnPrint         = $window.FindName("btnPrint")
$btnSettings      = $window.FindName("btnSettings")
$btnChangePw      = $window.FindName("btnChangePw")
$btnReset         = $window.FindName("btnReset")

# --- Initialization ---
$txtDate.Text = (Get-Date).ToString("MM/yyyy")
$txtLabelWidth.Text    = $script:Config.LabelWidthCm.ToString()
$txtLabelHeight.Text   = $script:Config.LabelHeightCm.ToString()
$txtPaddingMm.Text     = $script:Config.PaddingMm.ToString()
$txtHeaderPercent.Text = $script:Config.HeaderHeightPercent.ToString()
$txtLogoPercent.Text   = $script:Config.LogoHeightPercent.ToString()
$txtLogoPath.Text      = $script:Config.LogoPath

# Load printers
$printers = (Get-Printer | Where-Object { $_.Type -eq "Local" -or $_.Type -eq "Connection" }).Name
foreach ($p in $printers) { $cbPrinter.Items.Add($p) | Out-Null }
if ($script:Config.LastPrinter -and $cbPrinter.Items.Contains($script:Config.LastPrinter)) {
    $cbPrinter.SelectedItem = $script:Config.LastPrinter
} elseif ($cbPrinter.Items.Count -gt 0) {
    $cbPrinter.SelectedIndex = 0
}

# --- Global data ---
$script:Organizations   = @()
$script:AllDevices      = @()
$script:OrgLookup       = @{}
$script:CurrentOrgId    = $null
$script:OriginalOrgName = ""

# Store current org name override in config
function Update-OrgNameOverride {
    if (-not $script:CurrentOrgId) { return }
    $key = "$script:CurrentOrgId"
    $currentText = $txtOrgName.Text
    if ($currentText -and $currentText -ne $script:OriginalOrgName) {
        $script:Config.OrgNameOverrides[$key] = $currentText
    } else {
        if ($script:Config.OrgNameOverrides.ContainsKey($key)) {
            $script:Config.OrgNameOverrides.Remove($key)
        }
    }
}

# --- Establish connection ---
$btnConnect.Add_Click({

    # ── Step 1: Ensure decrypted credentials are available ──────────────

    # Case A – Encrypted credentials on disk, not yet unlocked
    if ((-not $script:Config.ClientId -or -not $script:Config.ClientSecret) -and
        $script:Config.MasterPasswordVerifier -and $script:Config.EncryptedClientId) {

        $mpXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="🔒 Master Password" Height="190" Width="420"
        WindowStartupLocation="CenterOwner" Background="#1e1e2e" ResizeMode="NoResize">
    <StackPanel Margin="20">
        <TextBlock Text="Enter master password:" Foreground="White" FontSize="13" FontWeight="SemiBold" Margin="0,0,0,6"/>
        <PasswordBox Name="mpPassword" Background="#2a2a3d" Foreground="White" Padding="6" FontSize="13" Margin="0,0,0,14"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="mpReset" Content="🔄 Reset" Background="#cc3333" Foreground="White"
                    FontSize="12" Padding="12,6" Margin="0,0,8,0" Cursor="Hand" BorderThickness="0"/>
            <Button Name="mpUnlock" Content="🔓 Unlock" Background="#5865f2" Foreground="White"
                    FontSize="12" Padding="12,6" Cursor="Hand" BorderThickness="0"/>
        </StackPanel>
    </StackPanel>
</Window>
"@
        $mr = New-Object System.Xml.XmlNodeReader ([xml]$mpXaml)
        $mw = [Windows.Markup.XamlReader]::Load($mr)
        $mw.Owner = $window

        # Enter key in password field → trigger unlock
        $mw.FindName("mpPassword").Add_KeyDown({
            param($sender, $e)
            if ($e.Key -eq [System.Windows.Input.Key]::Return) {
                $mw.FindName("mpUnlock").RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
            }
        })

        $mw.FindName("mpUnlock").Add_Click({
            $pw = $mw.FindName("mpPassword").Password
            if (-not $pw) { [System.Windows.MessageBox]::Show("Please enter password.", "Notice", "OK", "Warning"); return }
            if (-not (Test-MasterPassword -MasterPassword $pw -Verifier $script:Config.MasterPasswordVerifier)) {
                [System.Windows.MessageBox]::Show("Incorrect master password!", "Error", "OK", "Error"); return
            }
            try {
                $script:Config.ClientId     = Unprotect-String -CipherText $script:Config.EncryptedClientId     -MasterPassword $pw
                $script:Config.ClientSecret = Unprotect-String -CipherText $script:Config.EncryptedClientSecret -MasterPassword $pw
                $script:MasterPassword         = $pw
                $script:MasterPasswordVerifier = $script:Config.MasterPasswordVerifier
                $mw.DialogResult = $true; $mw.Close()
            } catch {
                [System.Windows.MessageBox]::Show("Decryption failed – data corrupted?`n$($_.Exception.Message)", "Error", "OK", "Error")
            }
        })

        $mw.FindName("mpReset").Add_Click({
            $answer = [System.Windows.MessageBox]::Show(
                "All stored credentials will be permanently deleted.`nContinue?",
                "Reset Credentials", "YesNo", "Warning")
            if ($answer -eq "Yes") {
                $script:Config.ClientId = ""; $script:Config.ClientSecret = ""
                $script:Config.EncryptedClientId = ""; $script:Config.EncryptedClientSecret = ""
                $script:Config.MasterPasswordVerifier = ""
                $script:MasterPassword = $null; $script:MasterPasswordVerifier = $null
                Save-AppConfig $script:Config
                $mw.DialogResult = $false; $mw.Close()
            }
        })

        if (-not $mw.ShowDialog()) {
            # After reset the user needs to re-enter credentials → fall through to Case C below
            if ($script:Config.ClientId -and $script:Config.ClientSecret) { return }
        }
    }

    # Case B – Legacy plaintext credentials (migration to encrypted storage)
    if ($script:Config.ClientId -and $script:Config.ClientSecret -and -not $script:MasterPassword) {
        $migrateXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="🔐 Security Upgrade" Height="260" Width="440"
        WindowStartupLocation="CenterOwner" Background="#1e1e2e" ResizeMode="NoResize">
    <StackPanel Margin="20">
        <TextBlock Text="🔐 Set Master Password" Foreground="#5865f2" FontSize="14" FontWeight="Bold" Margin="0,0,0,4"/>
        <TextBlock Text="Your API credentials will be stored using AES-256 encryption."
                   Foreground="#999" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,10"/>
        <TextBlock Text="Master password (min. 8 characters):" Foreground="White" FontSize="12"/>
        <PasswordBox Name="mMasterPw1" Background="#2a2a3d" Foreground="White" Padding="4" FontSize="12" Margin="0,2,0,4"/>
        <TextBlock Text="Repeat master password:" Foreground="White" FontSize="12"/>
        <PasswordBox Name="mMasterPw2" Background="#2a2a3d" Foreground="White" Padding="4" FontSize="12" Margin="0,2,0,12"/>
        <Button Name="mSave" Content="🔒 Encrypt" Background="#5865f2" Foreground="White"
                FontSize="12" Padding="14,6" HorizontalAlignment="Right" Cursor="Hand" BorderThickness="0"/>
    </StackPanel>
</Window>
"@
        $mgr = New-Object System.Xml.XmlNodeReader ([xml]$migrateXaml)
        $mgw = [Windows.Markup.XamlReader]::Load($mgr)
        $mgw.Owner = $window
        $mgw.FindName("mSave").Add_Click({
            $p1 = $mgw.FindName("mMasterPw1").Password
            $p2 = $mgw.FindName("mMasterPw2").Password
            if ($p1.Length -lt 8) { [System.Windows.MessageBox]::Show("Password must be at least 8 characters long.", "Notice", "OK", "Warning"); return }
            if ($p1 -ne $p2)     { [System.Windows.MessageBox]::Show("Passwords do not match.", "Notice", "OK", "Warning"); return }
            $script:MasterPassword         = $p1
            $script:MasterPasswordVerifier = New-MasterPasswordVerifier -MasterPassword $p1
            Save-AppConfig $script:Config
            $mgw.DialogResult = $true; $mgw.Close()
        })
        if (-not $mgw.ShowDialog()) { return }
    }

    # Case C – No credentials at all → full setup dialog
    if (-not $script:Config.ClientId -or -not $script:Config.ClientSecret) {
        $setupXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="NinjaOne API Setup" Height="500" Width="440"
        WindowStartupLocation="CenterOwner" Background="#1e1e2e" ResizeMode="NoResize">
    <StackPanel Margin="20">
        <TextBlock Text="🔐 Set Master Password" Foreground="#5865f2" FontSize="14" FontWeight="Bold" Margin="0,0,0,4"/>
        <TextBlock Text="This password protects your API credentials (AES-256)."
                   Foreground="#999" FontSize="11" Margin="0,0,0,8"/>
        <TextBlock Text="Master password (min. 8 characters):" Foreground="White" FontSize="12"/>
        <PasswordBox Name="sMasterPw1" Background="#2a2a3d" Foreground="White" Padding="4" FontSize="12" Margin="0,2,0,4"/>
        <TextBlock Text="Repeat master password:" Foreground="White" FontSize="12"/>
        <PasswordBox Name="sMasterPw2" Background="#2a2a3d" Foreground="White" Padding="4" FontSize="12" Margin="0,2,0,12"/>
        <Separator Background="#444466" Margin="0,0,0,12"/>
        <TextBlock Text="🔗 NinjaOne API Credentials" Foreground="#5865f2" FontSize="14" FontWeight="Bold" Margin="0,0,0,8"/>
        <TextBlock Text="Base URL:" Foreground="White" FontSize="12"/>
        <TextBox Name="sBaseUrl" Background="#2a2a3d" Foreground="White" Padding="4" FontSize="12" Margin="0,2,0,8"/>
        <TextBlock Text="Client ID:" Foreground="White" FontSize="12"/>
        <TextBox Name="sClientId" Background="#2a2a3d" Foreground="White" Padding="4" FontSize="12" Margin="0,2,0,8"/>
        <TextBlock Text="Client Secret:" Foreground="White" FontSize="12"/>
        <PasswordBox Name="sClientSecret" Background="#2a2a3d" Foreground="White" Padding="4" FontSize="12" Margin="0,2,0,8"/>
        <Button Name="sSave" Content="🔒 Encrypt and Connect" Background="#5865f2" Foreground="White"
                FontSize="12" Padding="14,6" HorizontalAlignment="Right" Margin="0,8,0,0" Cursor="Hand" BorderThickness="0"/>
    </StackPanel>
</Window>
"@
        $sr = New-Object System.Xml.XmlNodeReader ([xml]$setupXaml)
        $sw = [Windows.Markup.XamlReader]::Load($sr)
        $sw.Owner = $window
        $sw.FindName("sBaseUrl").Text = $script:Config.NinjaBaseUrl
        $sw.FindName("sSave").Add_Click({
            $p1 = $sw.FindName("sMasterPw1").Password
            $p2 = $sw.FindName("sMasterPw2").Password
            if ($p1.Length -lt 8) { [System.Windows.MessageBox]::Show("Password must be at least 8 characters long.", "Notice", "OK", "Warning"); return }
            if ($p1 -ne $p2)     { [System.Windows.MessageBox]::Show("Passwords do not match.", "Notice", "OK", "Warning"); return }
            $cid = $sw.FindName("sClientId").Text.Trim()
            $csec = $sw.FindName("sClientSecret").Password
            if (-not $cid -or -not $csec) { [System.Windows.MessageBox]::Show("Client ID and Client Secret are required.", "Notice", "OK", "Warning"); return }
            $script:Config.NinjaBaseUrl  = $sw.FindName("sBaseUrl").Text.Trim()
            $script:Config.ClientId      = $cid
            $script:Config.ClientSecret  = $csec
            $script:MasterPassword         = $p1
            $script:MasterPasswordVerifier = New-MasterPasswordVerifier -MasterPassword $p1
            Save-AppConfig $script:Config
            $sw.DialogResult = $true; $sw.Close()
        })
        if (-not $sw.ShowDialog()) { return }
    }

    # Get token
    $ok = Connect-NinjaOne -BaseUrl $script:Config.NinjaBaseUrl `
                           -ClientId $script:Config.ClientId `
                           -ClientSecret $script:Config.ClientSecret
    if (-not $ok) { return }

    # Load organizations
    $script:Organizations = @(Get-NinjaOrganizations)
    $script:OrgLookup = @{}
    foreach ($org in $script:Organizations) { $script:OrgLookup[$org.id] = $org.name }

    # Populate TreeView
    $tvOrganizations.Items.Clear()
    foreach ($org in ($script:Organizations | Sort-Object name)) {
        $item = New-Object System.Windows.Controls.TreeViewItem
        $item.Header = $org.name
        $item.Tag    = $org.id
        $item.Foreground = [System.Windows.Media.Brushes]::White
        $tvOrganizations.Items.Add($item) | Out-Null
    }

    # Load all devices for "Recently added"
    try {
        $script:AllDevices = @(Get-NinjaAllDevicesDetailed)
        $recentRaw = @($script:AllDevices |
            Sort-Object { $_.id } -Descending |
            Select-Object -First 20)
        $recentDevices = [System.Collections.ArrayList]::new()
        foreach ($dev in $recentRaw) {
            [void]$recentDevices.Add([PSCustomObject]@{
                SystemName = Get-DeviceDisplayName -Device $dev
                OrgName    = if ($script:OrgLookup.ContainsKey($dev.organizationId)) { $script:OrgLookup[$dev.organizationId] } else { "?" }
                AssetId    = $dev.id
                RawDevice  = $dev
            })
        }
        $dgRecent.ItemsSource = $recentDevices
    } catch {
        # Fallback: leave recent list empty
    }

    [System.Windows.MessageBox]::Show("Connected! $($script:Organizations.Count) organizations loaded.", "Success", "OK", "Information")
})

# --- Select organization → Load devices ---
$tvOrganizations.Add_SelectedItemChanged({
    $selected = $tvOrganizations.SelectedItem
    if (-not $selected -or -not $selected.Tag) { return }

    # Store previous override
    Update-OrgNameOverride

    $orgId   = $selected.Tag
    $orgName = $selected.Header.ToString()
    $script:CurrentOrgId    = $orgId
    $script:OriginalOrgName = $orgName

    # Load override from config if available
    $key = "$orgId"
    if ($script:Config.OrgNameOverrides.ContainsKey($key)) {
        $txtOrgName.Text = $script:Config.OrgNameOverrides[$key]
    } else {
        $txtOrgName.Text = $orgName
    }
    $txtDate.Text = (Get-Date).ToString("MM/yyyy")

    try {
        $devices = @(Get-NinjaDevicesByOrg -OrgId $orgId)
        $deviceList = [System.Collections.ArrayList]::new()
        foreach ($dev in $devices) {
            [void]$deviceList.Add([PSCustomObject]@{
                SystemName = Get-DeviceDisplayName -Device $dev
                NodeClass  = $dev.nodeClass
                AssetId    = $dev.id
                RawDevice  = $dev
            })
        }
        $dgDevices.ItemsSource = $deviceList
    } catch {
        [System.Windows.MessageBox]::Show("Error loading devices:`n$($_.Exception.Message)", "Error", "OK", "Error")
    }
})

# --- Select logo ---
$btnSelectLogo.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = "Images|*.png;*.jpg;*.jpeg;*.bmp;*.gif|All Files|*.*"
    $dlg.Title  = "Select Logo"
    if ($dlg.ShowDialog()) {
        $txtLogoPath.Text = $dlg.FileName
        $script:Config.LogoPath = $dlg.FileName
    }
})

# --- Helper: Parse number (comma or dot → InvariantCulture) ---
function Parse-NumberInvariant([string]$Text) {
    [double]::Parse($Text.Replace(",", "."), [System.Globalization.CultureInfo]::InvariantCulture)
}

# --- Draw preview ---
function Update-LabelPreview {
    $canvasPreview.Children.Clear()

    $canvasMaxW = $canvasPreview.Width    # 280
    $canvasMaxH = $canvasPreview.Height   # 175

    # Parse label size
    try {
        $labelWcm = Parse-NumberInvariant $txtLabelWidth.Text
        $labelHcm = Parse-NumberInvariant $txtLabelHeight.Text
    } catch { $labelWcm = 4.0; $labelHcm = 2.5 }
    if ($labelWcm -le 0) { $labelWcm = 4.0 }
    if ($labelHcm -le 0) { $labelHcm = 2.5 }

    # Parse settings
    try { $paddingMm = Parse-NumberInvariant $txtPaddingMm.Text } catch { $paddingMm = 0 }
    try { $headerPct = Parse-NumberInvariant $txtHeaderPercent.Text } catch { $headerPct = 22 }
    try { $logoPct   = Parse-NumberInvariant $txtLogoPercent.Text } catch { $logoPct = 22 }
    if ($paddingMm -lt 0) { $paddingMm = 0 }
    if ($headerPct -lt 0 -or $headerPct -gt 50) { $headerPct = 22 }
    if ($logoPct -lt 0 -or $logoPct -gt 50) { $logoPct = 22 }

    # Adjust canvas size to label proportions
    $labelAspect  = $labelWcm / $labelHcm
    $canvasAspect = $canvasMaxW / $canvasMaxH
    if ($labelAspect -gt $canvasAspect) {
        $cW = $canvasMaxW
        $cH = $canvasMaxW / $labelAspect
    } else {
        $cH = $canvasMaxH
        $cW = $canvasMaxH * $labelAspect
    }
    $offsetX = ($canvasMaxW - $cW) / 2
    $offsetY = ($canvasMaxH - $cH) / 2

    # Padding in canvas coordinates (mm → cm, then proportional scaling)
    $paddingCm = $paddingMm / 10.0
    $scale     = $cW / $labelWcm   # Canvas-Pixel pro cm
    $padPx     = $paddingCm * $scale

    # Content area after padding
    $contentX = $padPx
    $contentY = $padPx
    $contentW = $cW - 2 * $padPx
    $contentH = $cH - 2 * $padPx
    if ($contentW -lt 10) { $contentW = 10 }
    if ($contentH -lt 10) { $contentH = 10 }

    # White background
    $bg = New-Object System.Windows.Shapes.Rectangle
    $bg.Width  = $cW
    $bg.Height = $cH
    $bg.Fill   = [System.Windows.Media.Brushes]::White
    [System.Windows.Controls.Canvas]::SetLeft($bg, $offsetX)
    [System.Windows.Controls.Canvas]::SetTop($bg, $offsetY)
    $canvasPreview.Children.Add($bg) | Out-Null

    # Border around content area (identical to print logic)
    $border = New-Object System.Windows.Shapes.Rectangle
    $border.Width  = $contentW
    $border.Height = $contentH
    $border.Stroke = [System.Windows.Media.Brushes]::Black
    $border.StrokeThickness = 1
    [System.Windows.Controls.Canvas]::SetLeft($border, $offsetX + $contentX)
    [System.Windows.Controls.Canvas]::SetTop($border, $offsetY + $contentY)
    $canvasPreview.Children.Add($border) | Out-Null

    # --- Proportional calculation (identical to print logic) ---
    # All positions/sizes relative to contentW/contentH, same formulas as in print

    # Top bar with organization name
    $headerH = [Math]::Max(8, $contentH * $headerPct / 100)
    $header = New-Object System.Windows.Shapes.Rectangle
    $header.Width  = $contentW
    $header.Height = $headerH
    $header.Fill   = [System.Windows.Media.Brushes]::Black
    [System.Windows.Controls.Canvas]::SetLeft($header, $offsetX + $contentX)
    [System.Windows.Controls.Canvas]::SetTop($header, $offsetY + $contentY)
    $canvasPreview.Children.Add($header) | Out-Null

    # Org name: proportional font size (GDI+ pt → WPF px: × 4/3)
    $orgFontPt = [Math]::Max(7, $headerH * 0.45)
    $orgFontPx = $orgFontPt * (4.0 / 3.0)
    $orgTextW  = $contentW - 2  # small inner margin so text does not overflow the border
    $orgText = New-Object System.Windows.Controls.TextBlock
    $orgText.Text          = $txtOrgName.Text
    $orgText.Foreground    = [System.Windows.Media.Brushes]::White
    $orgText.FontFamily    = New-Object System.Windows.Media.FontFamily("Segoe UI")
    $orgText.FontSize      = $orgFontPx
    $orgText.FontWeight    = [System.Windows.FontWeights]::Bold
    $orgText.Width         = $orgTextW
    $orgText.TextAlignment = [System.Windows.TextAlignment]::Center
    $orgText.TextTrimming  = [System.Windows.TextTrimming]::CharacterEllipsis

    # Vertically centered in header
    $orgText.Measure([System.Windows.Size]::new($orgTextW, [double]::PositiveInfinity))
    $orgTextH = $orgText.DesiredSize.Height
    $orgTopOffset = [Math]::Max(0, ($headerH - $orgTextH) / 2)
    [System.Windows.Controls.Canvas]::SetLeft($orgText, $offsetX + $contentX + 1)
    [System.Windows.Controls.Canvas]::SetTop($orgText, $offsetY + $contentY + $orgTopOffset)
    $canvasPreview.Children.Add($orgText) | Out-Null

    # Determine device name
    $selectedDevices = @()
    if ($dgDevices.SelectedItems.Count -gt 0) {
        $selectedDevices = $dgDevices.SelectedItems
    } elseif ($dgRecent.SelectedItems.Count -gt 0) {
        $selectedDevices = $dgRecent.SelectedItems
    }
    $deviceName = if ($selectedDevices.Count -gt 0) { [string]$selectedDevices[0].SystemName } else { "DEVICE NAME" }

    # Device name: proportional font size with auto-shrink
    $devFontPt = [Math]::Max(8, $contentH * 0.15)
    $devFontPx = $devFontPt * (4.0 / 3.0)

    # Auto-shrink: reduce font size if text is too wide
    $devAvailW = $contentW - 10
    $minDevFontPx = 6
    $tempText = New-Object System.Windows.Controls.TextBlock
    $tempText.Text       = $deviceName
    $tempText.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
    $tempText.FontWeight = [System.Windows.FontWeights]::Bold
    $tempText.FontSize   = $devFontPx
    $tempText.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    while ($tempText.DesiredSize.Width -gt $devAvailW -and $devFontPx -gt $minDevFontPx) {
        $devFontPx = $devFontPx * 0.9
        $tempText.FontSize = $devFontPx
        $tempText.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    }

    $deviceText = New-Object System.Windows.Controls.TextBlock
    $deviceText.Text          = $deviceName
    $deviceText.Foreground    = [System.Windows.Media.Brushes]::Black
    $deviceText.FontFamily    = New-Object System.Windows.Media.FontFamily("Segoe UI")
    $deviceText.FontSize      = $devFontPx
    $deviceText.FontWeight    = [System.Windows.FontWeights]::Bold
    $deviceText.Width         = $contentW
    $deviceText.TextAlignment = [System.Windows.TextAlignment]::Center
    $deviceText.TextTrimming  = [System.Windows.TextTrimming]::CharacterEllipsis

    # Vertically centered in middle area (between header and footer)
    $deviceText.Measure([System.Windows.Size]::new($contentW, [double]::PositiveInfinity))
    $devTextH = $deviceText.DesiredSize.Height
    $middleTop = $contentY + $headerH
    $footerH = [Math]::Max(8, $contentH * $logoPct / 100)
    $middleH = $contentH - $headerH - $footerH
    $devTopOffset = $middleTop + [Math]::Max(0, ($middleH - $devTextH) / 2)
    [System.Windows.Controls.Canvas]::SetLeft($deviceText, $offsetX + $contentX)
    [System.Windows.Controls.Canvas]::SetTop($deviceText, $offsetY + $devTopOffset)
    $canvasPreview.Children.Add($deviceText) | Out-Null

    # Date bottom-left
    $dateFontPt = [Math]::Max(5, $contentH * 0.10)
    $dateFontPx = $dateFontPt * (4.0 / 3.0)
    $dateText = New-Object System.Windows.Controls.TextBlock
    $dateText.Text       = $txtDate.Text
    $dateText.Foreground = [System.Windows.Media.Brushes]::DimGray
    $dateText.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
    $dateText.FontWeight = [System.Windows.FontWeights]::SemiBold
    $dateText.FontSize   = $dateFontPx
    $dateText.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    $dateTextH = $dateText.DesiredSize.Height
    [System.Windows.Controls.Canvas]::SetLeft($dateText, $offsetX + $contentX + 6)
    [System.Windows.Controls.Canvas]::SetTop($dateText, $offsetY + $contentY + $contentH - $dateTextH - 4)
    $canvasPreview.Children.Add($dateText) | Out-Null

    # Logo bottom-right
    if ($txtLogoPath.Text -and (Test-Path $txtLogoPath.Text)) {
        try {
            $logoH = $footerH
            $bitmapImage = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmapImage.BeginInit()
            $bitmapImage.UriSource = New-Object System.Uri($txtLogoPath.Text)
            $bitmapImage.DecodePixelHeight = [int][Math]::Max(10, $logoH * 2)
            $bitmapImage.EndInit()

            $logoAspect = $bitmapImage.PixelWidth / [Math]::Max(1, $bitmapImage.PixelHeight)
            $logoW = $logoH * $logoAspect

            $img = New-Object System.Windows.Controls.Image
            $img.Source = $bitmapImage
            $img.Height = $logoH
            $img.Width  = $logoW
            [System.Windows.Controls.Canvas]::SetLeft($img, $offsetX + $contentX + $contentW - $logoW - 6)
            [System.Windows.Controls.Canvas]::SetTop($img, $offsetY + $contentY + $contentH - $logoH - 4)
            $canvasPreview.Children.Add($img) | Out-Null
        } catch { }
    }

    # Size indicator (outside the label, below)
    $sizeText = New-Object System.Windows.Controls.TextBlock
    $sizeText.Text       = "$($txtLabelWidth.Text) x $($txtLabelHeight.Text) cm"
    $sizeText.Foreground = [System.Windows.Media.Brushes]::Gray
    $sizeText.FontSize   = 9
    $sizeText.FontStyle  = [System.Windows.FontStyles]::Italic
    $sizeText.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    [System.Windows.Controls.Canvas]::SetLeft($sizeText, $offsetX + ($cW - $sizeText.DesiredSize.Width) / 2)
    [System.Windows.Controls.Canvas]::SetTop($sizeText, $offsetY + $cH + 2)
    $canvasPreview.Children.Add($sizeText) | Out-Null
}

# --- Auto-update preview on value changes ---
$txtOrgName.Add_TextChanged({ Update-LabelPreview })
$txtDate.Add_TextChanged({ Update-LabelPreview })
$txtLabelWidth.Add_TextChanged({ Update-LabelPreview })
$txtLabelHeight.Add_TextChanged({ Update-LabelPreview })
$txtPaddingMm.Add_TextChanged({ Update-LabelPreview })
$txtHeaderPercent.Add_TextChanged({ Update-LabelPreview })
$txtLogoPercent.Add_TextChanged({ Update-LabelPreview })
$txtLogoPath.Add_TextChanged({ Update-LabelPreview })

$dgDevices.Add_SelectionChanged({
    if ($dgDevices.SelectedItems.Count -gt 0) {
        $dgRecent.UnselectAll()
    }
    Update-LabelPreview
})
$dgRecent.Add_SelectionChanged({
    # On click on "Recently added" → apply org name and deselect upper list
    if ($dgRecent.SelectedItems.Count -gt 0) {
        $dgDevices.UnselectAll()
    }
    if ($dgRecent.SelectedItem) {
        # Store previous override
        Update-OrgNameOverride

        $devOrgId   = $dgRecent.SelectedItem.RawDevice.organizationId
        $devOrgName = $dgRecent.SelectedItem.OrgName
        $script:CurrentOrgId    = $devOrgId
        $script:OriginalOrgName = $devOrgName

        # Load override from config if available
        $key = "$devOrgId"
        if ($script:Config.OrgNameOverrides.ContainsKey($key)) {
            $txtOrgName.Text = $script:Config.OrgNameOverrides[$key]
        } else {
            $txtOrgName.Text = $devOrgName
        }
    }
    Update-LabelPreview
})

# --- Print ---
$btnPrint.Add_Click({
    $selectedPrinter = $cbPrinter.SelectedItem
    if (-not $selectedPrinter) {
        [System.Windows.MessageBox]::Show("Please select a printer!", "Notice", "OK", "Warning")
        return
    }

    # Collect devices (from both DataGrids)
    $devicesToPrint = @()
    if ($dgDevices.SelectedItems.Count -gt 0) {
        $devicesToPrint += $dgDevices.SelectedItems | ForEach-Object { $_.SystemName }
    }
    if ($dgRecent.SelectedItems.Count -gt 0) {
        $devicesToPrint += $dgRecent.SelectedItems | ForEach-Object { $_.SystemName }
    }

    if ($devicesToPrint.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Please select at least one device!", "Notice", "OK", "Warning")
        return
    }

    # Store printer and org override
    Update-OrgNameOverride
    $script:Config.LastPrinter = $selectedPrinter
    Save-AppConfig $script:Config

    # Calculate print dimensions (cm → 1/100 inch, 1cm = 0.3937 inch)
    $labelWcm = Parse-NumberInvariant $txtLabelWidth.Text
    $labelHcm = Parse-NumberInvariant $txtLabelHeight.Text
    $labelW100 = [int]($labelWcm * 0.3937 * 100)
    $labelH100 = [int]($labelHcm * 0.3937 * 100)

    # Capture configurable values
    try { $paddingMm = Parse-NumberInvariant $txtPaddingMm.Text } catch { $paddingMm = 0 }
    try { $headerPct = Parse-NumberInvariant $txtHeaderPercent.Text } catch { $headerPct = 22 }
    try { $logoPct   = Parse-NumberInvariant $txtLogoPercent.Text } catch { $logoPct = 22 }
    if ($paddingMm -lt 0) { $paddingMm = 0 }
    if ($headerPct -lt 0 -or $headerPct -gt 50) { $headerPct = 22 }
    if ($logoPct -lt 0 -or $logoPct -gt 50) { $logoPct = 22 }

    # Padding in 1/100 inch (mm → 1/100 inch: mm / 25.4 * 100)
    $pad100 = [int]($paddingMm / 25.4 * 100)

    foreach ($devName in $devicesToPrint) {
        $printDoc = New-Object System.Drawing.Printing.PrintDocument
        $printDoc.PrinterSettings.PrinterName = $selectedPrinter
        $printDoc.DefaultPageSettings.PaperSize = New-Object System.Drawing.Printing.PaperSize("Label", $labelW100, $labelH100)
        $printDoc.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(0, 0, 0, 0)

        $currentDevName  = $devName
        $currentOrgName  = $txtOrgName.Text
        $currentDate     = $txtDate.Text
        $currentLogo     = $txtLogoPath.Text
        $currentPad      = $pad100
        $currentHeaderPct = $headerPct
        $currentLogoPct  = $logoPct

        $printDoc.Add_PrintPage({
            param($sender, $e)
            $g = $e.Graphics
            $pageW = $e.PageBounds.Width
            $pageH = $e.PageBounds.Height

            # Content area after padding
            $cx = $currentPad
            $cy = $currentPad
            $w  = $pageW - 2 * $currentPad
            $h  = $pageH - 2 * $currentPad
            if ($w -lt 10) { $w = 10 }
            if ($h -lt 10) { $h = 10 }

            # Border around content area
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Black, 1)
            $g.DrawRectangle($pen, $cx, $cy, $w - 1, $h - 1)

            # Top bar
            $headerH = [int]($h * $currentHeaderPct / 100)
            $g.FillRectangle([System.Drawing.Brushes]::Black, $cx, $cy, $w - 1, $headerH)

            # Org name in bar
            $orgFont = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(7, $headerH * 0.45 * 96.0 / 100.0), [System.Drawing.FontStyle]::Bold)
            try {
                $orgSize = $g.MeasureString($currentOrgName, $orgFont)
                $g.DrawString($currentOrgName, $orgFont, [System.Drawing.Brushes]::White,
                    [int]($cx + ($w - $orgSize.Width) / 2), [int]($cy + ($headerH - $orgSize.Height) / 2))
            } finally { $orgFont.Dispose() }

            # Device name centered with auto-shrink
            $devFontSize = [Math]::Max(8, $h * 0.15 * 96.0 / 100.0)
            $devFont = New-Object System.Drawing.Font("Segoe UI", $devFontSize, [System.Drawing.FontStyle]::Bold)
            $devSize = $g.MeasureString($currentDevName, $devFont)
            $devAvailW = $w - 10
            while ($devSize.Width -gt $devAvailW -and $devFontSize -gt 5) {
                $devFontSize = $devFontSize * 0.9
                $devFont.Dispose()
                $devFont = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(5, $devFontSize), [System.Drawing.FontStyle]::Bold)
                $devSize = $g.MeasureString($currentDevName, $devFont)
            }

            # Vertical centering in middle area (between header and footer)
            $footerH = [int]($h * $currentLogoPct / 100)
            $middleTop = $cy + $headerH
            $middleH = $h - $headerH - $footerH
            try {
                $g.DrawString($currentDevName, $devFont, [System.Drawing.Brushes]::Black,
                    [int]($cx + ($w - $devSize.Width) / 2), [int]($middleTop + ($middleH - $devSize.Height) / 2))
            } finally { $devFont.Dispose() }

            # Date bottom-left
            $dateFont = New-Object System.Drawing.Font("Segoe UI", [Math]::Max(5, $h * 0.10 * 96.0 / 100.0), [System.Drawing.FontStyle]::Bold)
            try {
                $dateSize = $g.MeasureString($currentDate, $dateFont)
                $g.DrawString($currentDate, $dateFont, [System.Drawing.Brushes]::DimGray,
                    $cx + 6, [int]($cy + $h - $dateSize.Height - 4))
            } finally { $dateFont.Dispose() }

            # Logo bottom-right
            if ($currentLogo -and (Test-Path $currentLogo)) {
                try {
                    $logo = [System.Drawing.Image]::FromFile($currentLogo)
                    $logoH = $footerH
                    $logoW = [int]($logoH * ($logo.Width / $logo.Height))
                    $g.DrawImage($logo, [int]($cx + $w - $logoW - 6), [int]($cy + $h - $logoH - 4), $logoW, $logoH)
                    $logo.Dispose()
                } catch { }
            }
        })

        try {
            $printDoc.Print()
        } catch {
            [System.Windows.MessageBox]::Show("Print error: $($_.Exception.Message)", "Error", "OK", "Error")
            return
        }
    }

    [System.Windows.MessageBox]::Show("$($devicesToPrint.Count) label(s) printed!", "Done", "OK", "Information")
})

# --- Save settings ---
$btnSettings.Add_Click({
    $script:Config.LabelWidthCm       = Parse-NumberInvariant $txtLabelWidth.Text
    $script:Config.LabelHeightCm      = Parse-NumberInvariant $txtLabelHeight.Text
    $script:Config.PaddingMm           = Parse-NumberInvariant $txtPaddingMm.Text
    $script:Config.HeaderHeightPercent = Parse-NumberInvariant $txtHeaderPercent.Text
    $script:Config.LogoHeightPercent   = Parse-NumberInvariant $txtLogoPercent.Text
    $script:Config.LogoPath            = $txtLogoPath.Text
    $script:Config.LastPrinter         = $cbPrinter.SelectedItem
    Save-AppConfig $script:Config
    [System.Windows.MessageBox]::Show("Settings saved!", "OK", "OK", "Information")
})

# --- Reset credentials ---
$btnReset.Add_Click({
    $answer = [System.Windows.MessageBox]::Show(
        "All stored API credentials and the master password will be permanently deleted.`nContinue?",
        "Reset Credentials", "YesNo", "Warning")
    if ($answer -ne "Yes") { return }
    $script:Config.ClientId = ""; $script:Config.ClientSecret = ""
    $script:Config.EncryptedClientId = ""; $script:Config.EncryptedClientSecret = ""
    $script:Config.MasterPasswordVerifier = ""
    $script:MasterPassword = $null; $script:MasterPasswordVerifier = $null
    $script:AccessToken = $null
    Save-AppConfig $script:Config
    $tvOrganizations.Items.Clear()
    $dgDevices.ItemsSource  = $null
    $dgRecent.ItemsSource   = $null
    [System.Windows.MessageBox]::Show("Credentials deleted. Please reconnect.", "Reset", "OK", "Information")
})

# --- Change master password ---
$btnChangePw.Add_Click({
    if (-not $script:MasterPassword) {
        [System.Windows.MessageBox]::Show("No master password set. Please connect first.", "Notice", "OK", "Warning")
        return
    }
    $cpXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="🔑 Change Master Password" Height="300" Width="440"
        WindowStartupLocation="CenterOwner" Background="#1e1e2e" ResizeMode="NoResize">
    <StackPanel Margin="20">
        <TextBlock Text="Current password:" Foreground="White" FontSize="12"/>
        <PasswordBox Name="cpOldPw" Background="#2a2a3d" Foreground="White" Padding="4" FontSize="12" Margin="0,2,0,8"/>
        <TextBlock Text="New password (min. 8 characters):" Foreground="White" FontSize="12"/>
        <PasswordBox Name="cpNewPw1" Background="#2a2a3d" Foreground="White" Padding="4" FontSize="12" Margin="0,2,0,4"/>
        <TextBlock Text="Repeat new password:" Foreground="White" FontSize="12"/>
        <PasswordBox Name="cpNewPw2" Background="#2a2a3d" Foreground="White" Padding="4" FontSize="12" Margin="0,2,0,14"/>
        <Button Name="cpSave" Content="🔑 Change Password" Background="#5865f2" Foreground="White"
                FontSize="12" Padding="14,6" HorizontalAlignment="Right" Cursor="Hand" BorderThickness="0"/>
    </StackPanel>
</Window>
"@
    $cpr = New-Object System.Xml.XmlNodeReader ([xml]$cpXaml)
    $cpw = [Windows.Markup.XamlReader]::Load($cpr)
    $cpw.Owner = $window
    $cpw.FindName("cpSave").Add_Click({
        $oldPw = $cpw.FindName("cpOldPw").Password
        $newP1 = $cpw.FindName("cpNewPw1").Password
        $newP2 = $cpw.FindName("cpNewPw2").Password
        if ($oldPw -ne $script:MasterPassword) {
            [System.Windows.MessageBox]::Show("Current password is incorrect.", "Error", "OK", "Error"); return
        }
        if ($newP1.Length -lt 8) { [System.Windows.MessageBox]::Show("New password must be at least 8 characters long.", "Notice", "OK", "Warning"); return }
        if ($newP1 -ne $newP2)  { [System.Windows.MessageBox]::Show("New passwords do not match.", "Notice", "OK", "Warning"); return }
        $script:MasterPassword         = $newP1
        $script:MasterPasswordVerifier = New-MasterPasswordVerifier -MasterPassword $newP1
        Save-AppConfig $script:Config
        [System.Windows.MessageBox]::Show("Master password changed successfully!", "Success", "OK", "Information")
        $cpw.DialogResult = $true; $cpw.Close()
    })
    $cpw.ShowDialog() | Out-Null
})

# --- Initial preview ---
Update-LabelPreview

# --- Auto-open password dialog on start (if encrypted credentials exist) ---
$window.Add_ContentRendered({
    if ((-not $script:Config.ClientId -or -not $script:Config.ClientSecret) -and
        $script:Config.MasterPasswordVerifier -and $script:Config.EncryptedClientId) {
        $btnConnect.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    }
})

# --- Save org override on close ---
$window.Add_Closing({
    Update-OrgNameOverride
    Save-AppConfig $script:Config
})

# --- Show window ---
$window.ShowDialog() | Out-Null
