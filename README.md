# Test-Connections
Like Microsoft's Test-Connection, but in parallel, with color and with a "watch" option.

Works with [PowerShell](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7.2) as of now.

```powershell
Test-Connections -TargetName 1.1.1.1 -Watch
```

```powershell
Test-Connections -TargetName 1.1.1.1, 1.0.0.1, 8.8.4.4, 8.8.8.8, 9.9.9.9 -Watch
```

```powershell
Test-Connections 1.1.1.1, 1.0.0.1, 8.8.4.4, 8.8.8.8, 9.9.9.9 -Watch -Repeat
```

```powershell
Test-Connections 1.1.1.1, 1.0.0.1, 8.8.4.4, 8.8.8.8, 9.9.9.9 -Count 10 -Watch
```

Read from a file:

```powershell
Test-Connections $(Get-Content servers.txt) -Watch
```

## Pipelining
```powershell
@("1.1.1.1", "1.0.0.1", "8.8.4.4", "8.8.8.8", "9.9.9.9") | Test-Connections -Watch
```

```powershell
Connect-VIServer esxi.local
Get-VM | Test-Connections -Watch
```

```powershell
(1..10) | ForEach-Object { "192.168.0.$_" } | Test-Connections -Watch
```

Test before you run with -WhatIf

Please, please do not run this, that would generate 1622 * 4

```powershell
Invoke-WebRequest https://public-dns.info/nameserver/us.json | ConvertFrom-Json | Select-Object -ExpandProperty ip | Test-Connections -WhatIf
```
