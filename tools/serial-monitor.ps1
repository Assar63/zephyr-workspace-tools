# Open the configured serial port (Zephyr console).
# Defaults to COM3 @ 115200; override with PORT / BAUD env vars.
#
# Reads from the port and prints to the console; Ctrl-C to stop.

$ErrorActionPreference = 'Stop'

$Port = if ($env:PORT) { $env:PORT } else { 'COM3' }
$BaudInt = if ($env:BAUD) { [int]$env:BAUD } else { 115200 }

$AvailablePorts = [System.IO.Ports.SerialPort]::GetPortNames()
if ($AvailablePorts -notcontains $Port) {
    Write-Warning "Port $Port not detected. Available: $($AvailablePorts -join ', ')"
    Write-Warning "Set `$env:PORT to an available port and re-run."
    exit 1
}

$sp = New-Object System.IO.Ports.SerialPort $Port, $BaudInt, 'None', 8, 'One'
$sp.NewLine = "`n"
$sp.ReadTimeout = 250
$sp.Open()

Write-Host "Listening on $Port @ $BaudInt baud (Ctrl-C to stop)"
try {
    while ($true) {
        try {
            $line = $sp.ReadLine()
            Write-Host $line
        } catch [System.TimeoutException] {
            # ignore -- just retry
        }
    }
} finally {
    $sp.Close()
    $sp.Dispose()
}
