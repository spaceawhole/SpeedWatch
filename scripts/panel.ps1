# SpeedWatch - control panel
# A window you open when you want it. It holds no timer and no background work:
# the schedule lives in Windows Task Scheduler, and closing this window leaves
# nothing running.

$ErrorActionPreference = 'Stop'

try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
} catch {
    exit 1
}

$Root     = Split-Path -Parent $PSScriptRoot
$DataDir  = Join-Path $Root 'data'
$History  = Join-Path $DataDir 'history.ndjson'
$RunPs1   = Join-Path $PSScriptRoot 'run-test.ps1'
$Uninst   = Join-Path $PSScriptRoot 'uninstall.ps1'
$Report   = Join-Path $Root 'report\report.html'

. (Join-Path $PSScriptRoot 'schedule.ps1')

# palette
$cLine   = '#FF2A3743'
$cText   = '#FFE6EEF4'
$cMuted  = '#FF8FA2B0'
$cOk     = '#FF63B483'
$cBad    = '#FFE08A80'
$cWarn   = '#FFD2A054'

# Share-of-plan bands. Get-SwGrade (schedule.ps1) decides the band; this maps
# it to a colour. White means "neutral" - below par, but not worth alarming over.
$cGrade  = @{
    red    = '#FFE08A80'
    yellow = '#FFD2A054'
    white  = '#FFE6EEF4'
    green  = '#FF63B483'
}

$xamlText = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SpeedWatch" Height="880" Width="580" MinWidth="580" MaxWidth="580" MinHeight="640"
        ResizeMode="CanResize" WindowStartupLocation="CenterScreen"
        Background="#FF11171D" FontFamily="Segoe UI">
  <Grid Margin="26,22,26,18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- header -->
    <StackPanel Grid.Row="0" Margin="0,0,0,16">
      <TextBlock Text="SpeedWatch" Foreground="#FFE6EEF4" FontSize="24" FontWeight="SemiBold"/>
      <TextBlock x:Name="SubTitle" Text="" Foreground="#FF8FA2B0" FontSize="13" Margin="0,2,0,0" TextWrapping="Wrap"/>
    </StackPanel>

    <!-- on/off -->
    <Border Grid.Row="1" Background="#FF1B242D" CornerRadius="6" Padding="18" Margin="0,0,0,12">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" VerticalAlignment="Center">
          <TextBlock x:Name="StateLabel" Text="..." FontSize="17" FontWeight="SemiBold" Foreground="#FFE6EEF4"/>
          <TextBlock x:Name="NextRun" Text="" FontSize="12.5" Foreground="#FF8FA2B0" Margin="0,3,0,0" TextWrapping="Wrap"/>
        </StackPanel>
        <Button x:Name="BtnToggle" Grid.Column="1" Width="104" Height="42"
                Content="OFF" FontSize="15" FontWeight="SemiBold"
                Foreground="#FFFFFFFF" BorderThickness="0" Cursor="Hand">
          <Button.Template>
            <ControlTemplate TargetType="Button">
              <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="21">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Button.Template>
        </Button>
      </Grid>
    </Border>

    <!-- settings: plan + test times -->
    <Border Grid.Row="2" Background="#FF1B242D" CornerRadius="6" Padding="18" Margin="0,0,0,12">
      <StackPanel>
        <TextBlock Text="YOUR PLAN" FontSize="10" Foreground="#FF8FA2B0" Margin="0,0,0,8"/>
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" Text="Download" FontSize="12.5" Foreground="#FFE6EEF4"
                     VerticalAlignment="Center" Margin="0,0,8,0"/>
          <TextBox x:Name="PlanDown" Grid.Column="1" Width="78" Height="30"
                   VerticalContentAlignment="Center" HorizontalContentAlignment="Center"
                   Background="#FF11171D" Foreground="#FFE6EEF4" CaretBrush="#FFE6EEF4"
                   BorderBrush="#FF2A3743" BorderThickness="1" FontSize="13"/>
          <TextBlock Grid.Column="2" Text="Upload" FontSize="12.5" Foreground="#FFE6EEF4"
                     VerticalAlignment="Center" Margin="16,0,8,0"/>
          <TextBox x:Name="PlanUp" Grid.Column="3" Width="78" Height="30"
                   VerticalContentAlignment="Center" HorizontalContentAlignment="Center"
                   Background="#FF11171D" Foreground="#FFE6EEF4" CaretBrush="#FFE6EEF4"
                   BorderBrush="#FF2A3743" BorderThickness="1" FontSize="13"/>
          <TextBlock Grid.Column="4" Text="Mb/s" FontSize="12.5" Foreground="#FF8FA2B0"
                     VerticalAlignment="Center" Margin="8,0,0,0"/>
          <Button x:Name="BtnSavePlan" Grid.Column="5" Content="Save" Height="30" Width="72"
                  HorizontalAlignment="Right" Cursor="Hand"/>
        </Grid>
        <TextBlock x:Name="PlanHint" Text="" FontSize="11.5" Foreground="#FF8FA2B0"
                   Margin="0,8,0,0" TextWrapping="Wrap"/>

        <TextBlock Text="TEST TIMES" FontSize="10" Foreground="#FF8FA2B0" Margin="0,16,0,10"/>
        <WrapPanel x:Name="TimeList" Orientation="Horizontal"/>
        <Grid Margin="0,4,0,0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <TextBox x:Name="NewTime" Grid.Column="0" Width="74" Height="30"
                   VerticalContentAlignment="Center" HorizontalContentAlignment="Center"
                   Background="#FF11171D" Foreground="#FFE6EEF4" CaretBrush="#FFE6EEF4"
                   BorderBrush="#FF2A3743" BorderThickness="1" FontSize="13"/>
          <Button x:Name="BtnAddTime" Grid.Column="1" Content="Add" Height="30"
                  Margin="8,0,0,0" Padding="16,0" Cursor="Hand"/>
          <TextBlock x:Name="SchedHint" Grid.Column="2" Text="" FontSize="11.5"
                     Foreground="#FF8FA2B0" VerticalAlignment="Center"
                     Margin="12,0,0,0" TextWrapping="Wrap"/>
        </Grid>
      </StackPanel>
    </Border>

    <!-- latest result -->
    <Border Grid.Row="3" Background="#FF1B242D" CornerRadius="6" Padding="18" Margin="0,0,0,12">
      <StackPanel>
        <TextBlock x:Name="LastWhen" Text="No test yet" FontSize="12" Foreground="#FF8FA2B0"/>
        <Grid Margin="0,12,0,0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <StackPanel Grid.Column="0">
            <TextBlock Text="DOWNLOAD" FontSize="10" Foreground="#FF8FA2B0"/>
            <TextBlock x:Name="ValDown" Text="--" FontSize="26" FontWeight="SemiBold" Foreground="#FFE6EEF4"/>
            <TextBlock Text="Mb/s" FontSize="11" Foreground="#FF8FA2B0"/>
          </StackPanel>
          <StackPanel Grid.Column="1">
            <TextBlock Text="UPLOAD" FontSize="10" Foreground="#FF8FA2B0"/>
            <TextBlock x:Name="ValUp" Text="--" FontSize="26" FontWeight="SemiBold" Foreground="#FFE6EEF4"/>
            <TextBlock Text="Mb/s" FontSize="11" Foreground="#FF8FA2B0"/>
          </StackPanel>
          <StackPanel Grid.Column="2">
            <TextBlock Text="PING" FontSize="10" Foreground="#FF8FA2B0"/>
            <TextBlock x:Name="ValPing" Text="--" FontSize="26" FontWeight="SemiBold" Foreground="#FFE6EEF4"/>
            <TextBlock Text="ms" FontSize="11" Foreground="#FF8FA2B0"/>
          </StackPanel>
        </Grid>
        <TextBlock x:Name="PlanLabel" Text="" FontSize="11.5" Foreground="#FF8FA2B0" Margin="0,14,0,5"/>
        <Border Background="#FF2A3743" CornerRadius="3" Height="6" HorizontalAlignment="Stretch">
          <!-- Two star columns: the fill takes pct parts, the rest 100-pct.
               Scales with the window instead of assuming a pixel width. -->
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition x:Name="PlanFillCol" Width="0*"/>
              <ColumnDefinition x:Name="PlanRestCol" Width="1*"/>
            </Grid.ColumnDefinitions>
            <Border x:Name="PlanBar" Grid.Column="0" Background="#FFE08A80" CornerRadius="3" Height="6"/>
          </Grid>
        </Border>
        <TextBlock x:Name="UnitNote" Text="" FontSize="11" Foreground="#FF8FA2B0"
                   Margin="0,9,0,0" TextWrapping="Wrap"/>
      </StackPanel>
    </Border>

    <!-- history -->
    <Border Grid.Row="4" Background="#FF1B242D" CornerRadius="6" Padding="18,14,18,14">
      <DockPanel>
        <TextBlock DockPanel.Dock="Top" Text="RECENT RUNS" FontSize="10" Foreground="#FF8FA2B0" Margin="0,0,0,8"/>
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel x:Name="RecentList"/>
        </ScrollViewer>
      </DockPanel>
    </Border>

    <!-- actions -->
    <Grid Grid.Row="5" Margin="0,12,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="10"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="10"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Button x:Name="BtnRun"    Grid.Column="0" Height="38" Content="Run now"     Cursor="Hand"/>
      <Button x:Name="BtnReport" Grid.Column="2" Height="38" Content="Open report" Cursor="Hand"/>
      <Button x:Name="BtnFolder" Grid.Column="4" Height="38" Content="Open folder" Cursor="Hand"/>
    </Grid>

    <!-- footer -->
    <Grid Grid.Row="6" Margin="0,12,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <TextBlock Grid.Column="0" VerticalAlignment="Center" FontSize="11" Foreground="#FF8FA2B0"
                 TextWrapping="Wrap"
                 Text="Nothing runs in the background. The schedule lives in Task Scheduler and the test process exits when it finishes."/>
      <Button x:Name="BtnUninstall" Grid.Column="1" Content="Remove SpeedWatch"
              Background="Transparent" Foreground="#FFE08A80" BorderThickness="0"
              FontSize="11.5" Cursor="Hand" Padding="8,4"/>
    </Grid>
  </Grid>
</Window>
'@

$chipBtnXaml = @'
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
       xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
  <Setter Property="Background" Value="Transparent"/>
  <Setter Property="Foreground" Value="#FF8FA2B0"/>
  <Setter Property="BorderThickness" Value="0"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="3">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="Bd" Property="Background" Value="#FF3A4C5A"/>
            <Setter Property="Foreground" Value="#FFE08A80"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
'@

$btnStyleXaml = @'
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
       xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
  <Setter Property="Background" Value="#FF22303B"/>
  <Setter Property="Foreground" Value="#FFE6EEF4"/>
  <Setter Property="BorderThickness" Value="0"/>
  <Setter Property="FontSize" Value="13"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="5">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="Bd" Property="Background" Value="#FF2C3D4A"/>
          </Trigger>
          <Trigger Property="IsEnabled" Value="False">
            <Setter TargetName="Bd" Property="Opacity" Value="0.45"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
'@

try {
    $win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xamlText)))
} catch {
    [Windows.MessageBox]::Show("SpeedWatch could not build its window.`n`n$($_.Exception.Message)", 'SpeedWatch') | Out-Null
    exit 1
}

function C { param([string]$Hex) (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Hex) }

function Show-PanelError {
    param([string]$Where, $ErrorRecord, [string]$Friendly = 'Something went wrong.')
    try { Write-SwLog -Root $Root -Message "$Where : $($ErrorRecord.Exception.Message)" } catch { }
    try {
        Add-Content -LiteralPath (Join-Path $Root 'data\panel-error.log') -Encoding UTF8 -Value @"
[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Where
$($ErrorRecord.Exception.ToString())
$($ErrorRecord.ScriptStackTrace)

"@
    } catch { }
    try {
        [Windows.MessageBox]::Show($Friendly, 'SpeedWatch') | Out-Null
    } catch { }
}

$ui = @{}
foreach ($n in @('SubTitle','StateLabel','NextRun','BtnToggle','TimeList','NewTime','BtnAddTime',
                 'SchedHint','LastWhen','ValDown','ValUp','ValPing','PlanLabel','PlanBar','PlanFillCol','PlanRestCol','UnitNote',
                 'PlanDown','PlanUp','BtnSavePlan','PlanHint',
                 'RecentList','BtnRun','BtnReport','BtnFolder','BtnUninstall')) {
    $ui[$n] = $win.FindName($n)
}

$script:ChipBtnStyle = $null
try {
    $btnStyle = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$btnStyleXaml)))
    foreach ($b in @($ui.BtnRun, $ui.BtnReport, $ui.BtnFolder, $ui.BtnAddTime, $ui.BtnSavePlan)) { $b.Style = $btnStyle }
    $script:ChipBtnStyle = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$chipBtnXaml)))
} catch {
    # Cosmetic only - the panel works with default buttons - but say so in the
    # log rather than failing silently, which is how this once went unnoticed.
    try { Write-SwLog -Root $Root -Message "Button styles failed to load: $($_.Exception.Message)" } catch { }
}

# ---------------------------------------------------------------- data helpers

function Get-Task {
    Get-ScheduledTask -TaskName $SwTaskName -TaskPath $SwTaskPath -ErrorAction SilentlyContinue
}

function Get-Runs {
    param([int]$Last = 40)
    if (-not (Test-Path -LiteralPath $History)) { return @() }
    try {
        $lines = @(Get-Content -LiteralPath $History -Encoding UTF8 -ErrorAction Stop |
                   Where-Object { $_.Trim().Length -gt 0 })
        if ($lines.Count -gt $Last) { $lines = $lines[($lines.Count - $Last)..($lines.Count - 1)] }
        $out = New-Object System.Collections.ArrayList
        # Repair-SwText fixes names mangled by the old console decoding (box-drawing characters back into accents)
        foreach ($l in $lines) { try { [void]$out.Add(((Repair-SwText $l) | ConvertFrom-Json)) } catch { } }
        return @($out)
    } catch { return @() }
}

function Get-GradeColour {
    # Colour for a reading measured against a plan. No plan set -> neutral,
    # because a band means nothing without a target to compare against.
    param($Mbps, $Plan, $Bands, [string]$Neutral = $cText)
    if ($null -eq $Plan -or [double]$Plan -le 0 -or $null -eq $Mbps) { return $Neutral }
    return $cGrade[(Get-SwGrade (([double]$Mbps) / [double]$Plan * 100) $Bands)]
}

function Get-ReadingPlan {
    # A reading is graded against the plan recorded with it; readings taken
    # before plans were recorded (or with none set) use the current plan.
    param($Recorded, $Current)
    $n = $null
    if ($null -ne $Recorded) { try { $n = [double]$Recorded } catch { $n = $null } }
    if ($null -ne $n -and $n -gt 0) { return $n }
    return $Current
}

function New-Row {
    param($Run, $Plan = $null, $PlanUp = $null, $Bands = $null)

    $g = New-Object System.Windows.Controls.Grid
    $g.Margin = '0,0,0,7'
    foreach ($w in @('118','*','64','64','Auto')) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        if ($w -eq '*')        { $cd.Width = New-Object System.Windows.GridLength(1, ([System.Windows.GridUnitType]::Star)) }
        elseif ($w -eq 'Auto') { $cd.Width = [Windows.GridLength]::Auto }
        else                   { $cd.Width = New-Object System.Windows.GridLength([double]$w) }
        $g.ColumnDefinitions.Add($cd)
    }

    function Cell {
        param([string]$Text, [int]$Col, [string]$Colour, [string]$Align = 'Left', [double]$Size = 12.5)
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $Text
        $tb.FontSize = $Size
        $tb.Foreground = (C $Colour)
        $tb.HorizontalAlignment = $Align
        $tb.VerticalAlignment = 'Center'
        $tb.Margin = '0,0,10,0'
        $tb.TextTrimming = 'CharacterEllipsis'
        [Windows.Controls.Grid]::SetColumn($tb, $Col)
        return $tb
    }

    $when = ''
    try { $when = ([datetime]$Run.ts).ToString('dd MMM  HH:mm') } catch { $when = [string]$Run.date }
    $g.Children.Add((Cell $when 0 $cMuted)) | Out-Null

    if ($Run.ok) {
        $label = [string]$Run.server
        if ($Run.engine -eq 'cloudflare') { $label = "$label (fallback)" }
        $g.Children.Add((Cell $label 1 $cMuted 'Left' 11.5)) | Out-Null
        $g.Children.Add((Cell ('{0}' -f $Run.downMbps) 2 (Get-GradeColour $Run.downMbps (Get-ReadingPlan $Run.planMbps $Plan) $Bands) 'Right')) | Out-Null
        $g.Children.Add((Cell ('{0}' -f $Run.upMbps)   3 (Get-GradeColour $Run.upMbps (Get-ReadingPlan $Run.planUpMbps $PlanUp) $Bands $cMuted) 'Right')) | Out-Null
        $g.Children.Add((Cell 'ok' 4 $cOk 'Right' 11)) | Out-Null
    } else {
        $g.Children.Add((Cell 'test failed' 1 $cBad 'Left' 11.5)) | Out-Null
        $g.Children.Add((Cell '--' 2 $cMuted 'Right')) | Out-Null
        $g.Children.Add((Cell '--' 3 $cMuted 'Right')) | Out-Null
        $g.Children.Add((Cell '!' 4 $cBad 'Right' 11)) | Out-Null
    }
    return $g
}

function New-TimeChip {
    param([string]$Time)

    $b = New-Object System.Windows.Controls.Border
    $b.Background   = (C '#FF22303B')
    $b.CornerRadius = New-Object System.Windows.CornerRadius(4)
    $b.Padding      = '10,4,6,4'
    $b.Margin       = '0,0,8,8'

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'

    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Time
    $tb.FontSize = 13
    $tb.Foreground = (C $cText)
    $tb.VerticalAlignment = 'Center'
    $sp.Children.Add($tb) | Out-Null

    $x = New-Object System.Windows.Controls.Button
    $x.Content = 'x'
    $x.Tag = $Time
    $x.Width = 20
    $x.Height = 20
    $x.Margin = '8,0,0,0'
    $x.FontSize = 12
    $x.Background = (C '#FF22303B')
    $x.Foreground = (C $cMuted)
    $x.BorderThickness = New-Object System.Windows.Thickness(0)
    $x.Cursor = 'Hand'
    $x.ToolTip = "Remove $Time"
    if ($script:ChipBtnStyle) { $x.Style = $script:ChipBtnStyle }
    $x.Add_Click({
        try {
            $src = if ($this) { $this } else { $args[0] }
            $t   = $src.Tag
            $st  = Get-SwSettings -Root $Root
            $remaining = @(@($st.times) | Where-Object { $_ -ne $t })
            if ($remaining.Count -eq 0) {
                [Windows.MessageBox]::Show('Keep at least one test time. Add another before removing this one.',
                                           'SpeedWatch') | Out-Null
                return
            }
            Set-Schedule -Times $remaining
        } catch { Show-PanelError -Where 'Removing a test time' -ErrorRecord $_ `
                    -Friendly 'Could not remove that time. Please try again.' }
    })
    $sp.Children.Add($x) | Out-Null

    $b.Child = $sp
    return $b
}

function Set-Schedule {
    param([string[]]$Times)
    try {
        $applied = Set-SwSchedule -Root $Root -Times $Times
        $st = Get-SwSettings -Root $Root
        $st.times = $applied
        Save-SwSettings -Root $Root -Settings $st
        Update-Ui
    } catch {
        Show-PanelError -Where 'Changing the schedule' -ErrorRecord $_ `
            -Friendly 'Could not update the test times. Please try again.'
    }
}

function Set-PlanBar {
    # Fraction of the bar filled, 0-100. Proportional, so it is right at any window width.
    param([double]$Percent)
    # 0.0 / 100.0, not 0 / 100: with an integer first argument PowerShell picks
    # the Int32 overload and rounds the fraction away ([math]::Min(100, 38.5) is 38).
    $f = [math]::Max(0.0, [math]::Min(100.0, $Percent))
    if ($f -gt 0 -and $f -lt 0.6) { $f = 0.6 }   # keep a sliver visible for tiny readings
    $ui.PlanFillCol.Width = New-Object System.Windows.GridLength($f, ([System.Windows.GridUnitType]::Star))
    $ui.PlanRestCol.Width = New-Object System.Windows.GridLength((100 - $f), ([System.Windows.GridUnitType]::Star))
}

function Update-Ui {
    $task     = Get-Task
    $settings = Get-SwSettings -Root $Root
    $times    = @($settings.times)
    $plan     = $settings.planMbps
    $planUp   = $settings.planUpMbps
    $bands    = $settings.bands

    if ($times.Count -eq 1) { $ui.SubTitle.Text = "One speed test a day, at $($times[0])" }
    else { $ui.SubTitle.Text = "$($times.Count) speed tests a day, at " + ($times -join ', ') }

    # --- test times ---
    $ui.TimeList.Children.Clear()
    foreach ($t in $times) { $ui.TimeList.Children.Add((New-TimeChip -Time $t)) | Out-Null }
    $ui.SchedHint.Text = 'Add a time as HH:MM, 24-hour.'

    # --- on/off ---
    if (-not $task) {
        $ui.StateLabel.Text = 'Not installed'
        $ui.StateLabel.Foreground = (C $cWarn)
        $ui.NextRun.Text = 'Run Install.cmd to create the scheduled task.'
        $ui.BtnToggle.Content = '--'
        $ui.BtnToggle.Background = (C $cLine)
        $ui.BtnToggle.IsEnabled = $false
    } else {
        $on = ($task.State -ne 'Disabled')
        if ($on) {
            $ui.StateLabel.Text = 'On'
            $ui.StateLabel.Foreground = (C $cOk)
            $ui.BtnToggle.Content = 'ON'
            $ui.BtnToggle.Background = (C $cOk)
            $next = $null
            try { $next = (Get-ScheduledTaskInfo -TaskName $SwTaskName -TaskPath $SwTaskPath).NextRunTime } catch { }
            if ($next) { $ui.NextRun.Text = 'Next test ' + ([datetime]$next).ToString('ddd d MMM, HH:mm') }
            else       { $ui.NextRun.Text = 'Next test at ' + ($times -join ' / ') }
        } else {
            $ui.StateLabel.Text = 'Off'
            $ui.StateLabel.Foreground = (C $cMuted)
            $ui.BtnToggle.Content = 'OFF'
            $ui.BtnToggle.Background = (C $cLine)
            $ui.NextRun.Text = 'No tests will run while this is off.'
        }
        $ui.BtnToggle.IsEnabled = $true
    }

    # --- latest reading ---
    $runs = Get-Runs -Last 60
    $ok   = @($runs | Where-Object { $_.ok })
    $last = if ($ok.Count) { $ok[-1] } else { $null }

    if ($last) {
        $ui.LastWhen.Text = 'Last test ' + ([datetime]$last.ts).ToString('ddd d MMM, HH:mm')
        $ui.ValDown.Text  = '{0:N1}' -f [double]$last.downMbps
        $ui.ValUp.Text    = '{0:N1}' -f [double]$last.upMbps
        $ui.ValPing.Text  = '{0:N0}' -f [double]$last.pingMs
        $ui.ValUp.Foreground = (C (Get-GradeColour $last.upMbps (Get-ReadingPlan $last.planUpMbps $planUp) $bands))

        $pct = 0
        if ($null -ne $plan -and [double]$plan -gt 0) {
            $pct = ([double]$last.downMbps) / [double]$plan * 100
            $ui.PlanLabel.Text = '{0:N1}% of the {1} Mb/s plan' -f $pct, (Format-Mbps $plan)
        } else {
            $ui.PlanLabel.Text = 'Enter your plan speed above to see how each reading compares.'
        }
        # Spell out the unit: Mb/s (megabits) is what plans are sold in and what
        # speed tests report; MB/s (megabytes) is what a browser download shows.
        $ui.UnitNote.Text = 'Mb/s = megabits per second, the unit plans are sold in. {0:N1} Mb/s is about {1:N1} MB/s (megabytes) in a browser download.' -f ([double]$last.downMbps), ([double]$last.downMbps / 8)

        if ($null -ne $plan) { Set-PlanBar $pct } else { Set-PlanBar 0 }
        $gradeColour = Get-GradeColour $last.downMbps (Get-ReadingPlan $last.planMbps $plan) $bands
        $ui.PlanBar.Background   = (C $gradeColour)
        $ui.ValDown.Foreground   = (C $gradeColour)
    } else {
        $ui.LastWhen.Text  = 'No successful test recorded yet'
        $ui.PlanLabel.Text = ''
        $ui.UnitNote.Text  = ''
        Set-PlanBar 0
    }

    # --- recent runs ---
    $ui.RecentList.Children.Clear()
    if ($runs.Count -eq 0) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = 'Nothing recorded yet. Press "Run now" to take the first reading.'
        $tb.FontSize = 12
        $tb.TextWrapping = 'Wrap'
        $tb.Foreground = (C $cMuted)
        $ui.RecentList.Children.Add($tb) | Out-Null
    } else {
        $recent = @($runs); [array]::Reverse($recent)
        foreach ($r in ($recent | Select-Object -First 12)) {
            $ui.RecentList.Children.Add((New-Row -Run $r -Plan $plan -PlanUp $planUp -Bands $bands)) | Out-Null
        }
    }
}

# ---------------------------------------------------------------- running a test

$script:proc  = $null
$script:timer = $null

function Start-Test {
    if ($script:proc -and -not $script:proc.HasExited) { return }

    $ui.BtnRun.IsEnabled = $false
    $ui.BtnRun.Content   = 'Running...'
    $ui.LastWhen.Text    = 'Testing - about 30 seconds, longer if it has to retry'

    try {
        $script:proc = Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Hidden `
            -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
                            '-File', ('"{0}"' -f $RunPs1), '-Manual')
    } catch {
        $ui.BtnRun.IsEnabled = $true
        $ui.BtnRun.Content   = 'Run now'
        [Windows.MessageBox]::Show("Could not start the test.`n`n$($_.Exception.Message)", 'SpeedWatch') | Out-Null
        return
    }

    $script:timer = New-Object System.Windows.Threading.DispatcherTimer
    $script:timer.Interval = [TimeSpan]::FromMilliseconds(700)
    $script:timer.Add_Tick({
        if ($script:proc -and $script:proc.HasExited) {
            $script:timer.Stop()
            $script:proc = $null
            $ui.BtnRun.IsEnabled = $true
            $ui.BtnRun.Content   = 'Run now'
            Update-Ui
        }
    })
    $script:timer.Start()
}

function Invoke-CatchUp {
    # "If it was off at a scheduled time, run when available" - on switching back
    # on, take the reading straight away if one is owed for today.
    try {
        $st  = Get-SwSettings -Root $Root
        $due = Get-SwLastDueTime -Times $st.times
        if (-not $due) { return }
        foreach ($r in (Get-Runs -Last 20)) {
            try { if (([datetime]$r.ts) -ge $due) { return } } catch { }
        }
        Start-Test
    } catch { }
}

# ---------------------------------------------------------------- events

$ui.BtnToggle.Add_Click({
    $task = Get-Task
    if (-not $task) { return }
    try {
        if ($task.State -eq 'Disabled') {
            Enable-ScheduledTask -TaskName $SwTaskName -TaskPath $SwTaskPath | Out-Null
            Update-Ui
            Invoke-CatchUp
        } else {
            Disable-ScheduledTask -TaskName $SwTaskName -TaskPath $SwTaskPath | Out-Null
            Update-Ui
        }
    } catch {
        [Windows.MessageBox]::Show("Could not change the schedule.`n`n$($_.Exception.Message)", 'SpeedWatch') | Out-Null
    }
})

function Add-TimeFromBox {
  try {
    $raw  = [string]$ui.NewTime.Text
    $norm = @(ConvertTo-SwTimes @($raw))
    if ($norm.Count -eq 0) {
        $ui.SchedHint.Text = "Wrong format. Please use HH:MM - for example 09:30"
        return
    }
    $st = Get-SwSettings -Root $Root
    if (@($st.times) -contains $norm[0]) {
        $ui.SchedHint.Text = "$($norm[0]) is already in the list."
        return
    }
    $ui.NewTime.Text = ''
    Set-Schedule -Times (@($st.times) + $norm)
  } catch { Show-PanelError -Where 'Adding a test time' -ErrorRecord $_ `
                  -Friendly 'Could not add that time. Please try again.' }
}

$ui.BtnAddTime.Add_Click({ Add-TimeFromBox })

function Format-Mbps {
    # Plain, separator-free, so "1000" never renders as the ambiguous "1.000".
    param($Value)
    if ($null -eq $Value) { return '' }
    $d = [double]$Value
    if ($d -eq [math]::Floor($d)) { return ([long]$d).ToString([Globalization.CultureInfo]::InvariantCulture) }
    return $d.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture)
}

function Show-PlanFields {
    # Only called at start and after a save - never from Update-Ui, which runs
    # when a test finishes and would otherwise wipe what someone is typing.
    $st = Get-SwSettings -Root $Root
    $ui.PlanDown.Text = Format-Mbps $st.planMbps
    $ui.PlanUp.Text   = Format-Mbps $st.planUpMbps
    if ($null -eq $st.planMbps) {
        $ui.PlanHint.Text = 'Enter the download speed your plan is sold at, in Mb/s (a 1000 megas plan is 1000). Upload is optional.'
    } else {
        $ui.PlanHint.Text = 'Speeds in Mb/s - megabits per second, the unit plans are sold in. Upload is optional.'
    }
}

function Save-PlanFromFields {
  try {
    $downRaw = [string]$ui.PlanDown.Text
    $upRaw   = [string]$ui.PlanUp.Text
    $down = ConvertTo-SwMbps $downRaw
    $up   = ConvertTo-SwMbps $upRaw

    if ($downRaw.Trim() -ne '' -and $null -eq $down) {
        $ui.PlanHint.Text = 'Wrong format for download. Please use a number in Mb/s - for example 1000'
        return
    }
    if ($upRaw.Trim() -ne '' -and $null -eq $up) {
        $ui.PlanHint.Text = 'Wrong format for upload. Please use a number in Mb/s - for example 100, or leave it empty'
        return
    }

    $st = Get-SwSettings -Root $Root
    $st.planMbps   = $down
    $st.planUpMbps = $up
    Save-SwSettings -Root $Root -Settings $st
    $planMsg = "Plan set to $(Format-Mbps $down) Mb/s download"
    if ($null -ne $up) { $planMsg += ", $(Format-Mbps $up) Mb/s upload" }
    Write-SwLog -Root $Root -Message $planMsg

    Show-PlanFields
    $ui.PlanHint.Text = 'Saved.'
    Update-Ui
  } catch { Show-PanelError -Where 'Saving the plan' -ErrorRecord $_ `
                  -Friendly 'Could not save the plan. Please try again.' }
}

$ui.BtnSavePlan.Add_Click({ Save-PlanFromFields })
foreach ($box in @($ui.PlanDown, $ui.PlanUp)) {
    $box.Add_KeyDown({
        $e = if ($args.Count -gt 1) { $args[1] } else { $_ }
        if ($e -and $e.Key -eq 'Return') { Save-PlanFromFields }
    })
}
$ui.NewTime.Add_KeyDown({
    $e = if ($args.Count -gt 1) { $args[1] } else { $_ }
    if ($e -and $e.Key -eq 'Return') { Add-TimeFromBox }
})

$ui.BtnRun.Add_Click({ Start-Test })

$ui.BtnReport.Add_Click({
    # Refresh the report's copy of the history first, so it opens current
    # (and with any repaired names) rather than as of the last test.
    try { Write-SwReportData -Root $Root -Settings (Get-SwSettings -Root $Root) } catch { }
    if (Test-Path -LiteralPath $Report) { Start-Process -FilePath $Report }
    else { [Windows.MessageBox]::Show('The report file is missing from the report folder.', 'SpeedWatch') | Out-Null }
})

$ui.BtnFolder.Add_Click({ Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $Root) })

$ui.BtnUninstall.Add_Click({
    $msg = "This removes the scheduled task and the desktop shortcut.`n`n" +
           "You will then be asked whether to delete the recorded results.`n" +
           "Afterwards you can simply delete the SpeedWatch folder.`n`nContinue?"
    if ([Windows.MessageBox]::Show($msg, 'Remove SpeedWatch', 'YesNo', 'Question') -eq 'Yes') {
        Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File', ('"{0}"' -f $Uninst))
        $win.Close()
    }
})

$win.Add_Closed({ if ($script:timer) { try { $script:timer.Stop() } catch { } } })

try {
    # Never taller than the screen: on a 768px laptop the full layout would
    # otherwise open with its buttons below the taskbar.
    try {
        $wa = [System.Windows.SystemParameters]::WorkArea.Height
        if ($wa -gt 0) { $win.Height = [math]::Max(640, [math]::Min(880, $wa - 24)) }
    } catch { }
    Show-PlanFields
    Update-Ui
    $win.ShowDialog() | Out-Null
} catch {
    Show-PanelError -Where 'Opening the panel' -ErrorRecord $_ `
        -Friendly 'SpeedWatch could not open.'
}
