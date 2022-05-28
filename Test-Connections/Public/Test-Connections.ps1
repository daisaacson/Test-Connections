function Test-Connections {
    <#
        .Synopsis
            Test-Connection to multiple devices in parallel.
        .Description
            Test-Connection to multiple devcies in parallel with a color and "watch" feature.
        .Example
            Test-Connections -TargetName 1.1.1.1 -Watch
        .Example
            Test-Connections -TargetName 1.1.1.1, 1.0.0.1, 8.8.4.4, 8.8.8.8, 9.9.9.9 -Watch
        .Example
            Test-Connections 1.1.1.1, 1.0.0.1, 8.8.4.4, 8.8.8.8, 9.9.9.9 -Watch -Repeat
        .Example
            Test-Connections 1.1.1.1, 1.0.0.1, 8.8.4.4, 8.8.8.8, 9.9.9.9 -Count 10 -Watch
        .Example
            Test-Connections $(Get-Content servers.txt) -Watch
        .Example
            @("1.1.1.1", "1.0.0.1", "8.8.4.4", "8.8.8.8", "9.9.9.9") | Test-Connections -Watch
        .Example
            Connect-VIServer esxi.local
            Get-VM | Test-Connections -Watch
        .Example
            (1..10) | ForEach-Object { "192.168.0.$_" } | Test-Connections -Watch
        .Notes
            Name: Test-Connections
            Author: David Isaacson
            Last Edit: 2022-04-24
            Keywords: Test-Connection, ping, icmp
        .Link
            https://github.com/daisaacson/test-connections
        .Inputs
            TargetName[]
        .Outputs
            none
        #Requires -Version 2.0
    #>
    [CmdletBinding(SupportsShouldProcess = $True)]
    Param (
        [Parameter(Mandatory = $True, ValueFromPipeline = $True, HelpMessage = "Stop after sending Count pings")]
        [string[]]$TargetName,

        [Parameter(Mandatory = $False)]
        [Alias("c")]
        [int]$Count = 4,

        [Parameter(Mandatory = $False, HelpMessage = "Continjously send pings")]
        [Alias("Continuous", "t")]
        [switch]$Repeat,

        [Parameter(Mandatory = $False, HelpMessage = "Delay between pings")]
        [int]$Delay = 1,

        [Parameter(Mandatory = $False, HelpMessage = "Interval between pings")]
        [Alias("u")]
        [int]$Update = 1000,

        [Parameter(Mandatory = $False, HelpMessage = "Watch")]
        [Alias("w")]
        [Switch]$Watch
    )

    Begin {
        Write-Verbose -Message "Begin $($MyInvocation.MyCommand)"
        $Targets = @()
        # Destingwish between Windows PowerShell and PowerShell Core
        $WindowsPowerShell = $PSVersionTable.PSEdition -and $PSVersionTable.PSEdition -eq 'Desktop'
        $PowerShellCore = ! $WindowsPowerShell
    }

    Process {
        Write-Verbose -Message "Process $($MyInvocation.MyCommand)"
        If ($pscmdlet.ShouldProcess("$TargetName")) {
            ForEach ($Target in $TargetName) {
                Write-Verbose -Message "$Target, $Count, $Delay, $Repeat"
                Try {
                    If ($WindowsPowerShell) {
                        # Create new Target and Start-Job
                        # Windows PowerShell 5.1 Test-Connection sucks, wrapper for Test-Connection to behave more like Test-Connection in PowerShell Core
                        $Targets += [Target]::new($Target, $(Start-Job -ScriptBlock $([ScriptBlock]::Create({
                                            Param ([String]$TargetName, [int]$Count = 4, [int]$Delay = 1, [bool]$Repeat)
                                            $Ping = 0
                                            While ($Repeat -or $Count -gt $Ping) {
                                                Write-Verbose "$($Repeat) $($Count) $($Ping)"
                                                $Ping++
                                                $icmp = Test-Connection -ComputerName $TargetName -Count 1 -ErrorAction SilentlyContinue
                                                If ($icmp) {
                                                    [PSCustomObject]@{
                                                        Ping    = $Ping;
                                                        Status  = "Success"
                                                        Latency = $icmp.ResponseTime
                                                    }
                                                } else {
                                                    [PSCustomObject]@{
                                                        Ping    = $Ping
                                                        Status  = "Failed"
                                                        Latency = 9999
                                                    }
                                                }
                                                Start-Sleep -Seconds $Delay
                                            }
                                        }
                                    )
                                ) -ArgumentList $Target, $Count, $Delay, $Repeat
                            )
                        )
                    } else {
                        If ($Repeat) {
                            $Targets += [Target]::new($Target, $(Start-Job -ScriptBlock $([ScriptBlock]::Create({ Param ($Target) Test-Connection -TargetName $Target -Ping -Repeat })) -ArgumentList $Target))
                        } else {
                            $Targets += [Target]::new($Target, $(Start-Job -ScriptBlock $([ScriptBlock]::Create({ Param ($Target, $Count) Test-Connection -TargetName $Target -Ping -Count $Count })) -ArgumentList $Target, $Count))
                        }
                    }
                } Catch { $_ }
            }
        }
    }

    End {
        Write-Verbose -Message "End $($MyInvocation.MyCommand)"
        If ($pscmdlet.ShouldProcess("$TargetName")) {
            # https://blog.sheehans.org/2018/10/27/powershell-taking-control-over-ctrl-c/
            # Change the default behavior of CTRL-C so that the script can intercept and use it versus just terminating the script.
            [Console]::TreatControlCAsInput = $True
            # Sleep for 1 second and then flush the key buffer so any previously pressed keys are discarded and the loop can monitor for the use of
            #   CTRL-C. The sleep command ensures the buffer flushes correctly.
            Start-Sleep -Seconds 1
            $Host.UI.RawUI.FlushInputBuffer()
            # Continue to loop while there are pending or currently executing jobs.
            While ($Targets.Job.HasMoreData -contains "True") {
                # If a key was pressed during the loop execution, check to see if it was CTRL-C (aka "3"), and if so exit the script after clearing
                #   out any running jobs and setting CTRL-C back to normal.
                If ($Host.UI.RawUI.KeyAvailable -and ($Key = $Host.UI.RawUI.ReadKey("AllowCtrlC,NoEcho,IncludeKeyUp"))) {
                    If ([Int]$Key.Character -eq 3) {
                        Write-Warning -Message "Removing Test-Connection Jobs"
                        If ($PowerShellCore) { Write-Host "`e[2A" }
                        $Targets.Job | Remove-Job -Force
                        $killed = $True
                        [Console]::TreatControlCAsInput = $False

                        break
                    }
                    # Flush the key buffer again for the next loop.
                    $Host.UI.RawUI.FlushInputBuffer()
                }
                # Perform other work here such as process pending jobs or process out current jobs.

                # Get Test-Connection updates
                $Targets.Update()

                # Print Output
                $Targets.ToTable() | Format-Table

                # Move cursor up to overwrite old output
                If ($Watch -and $PowerShellCore) {
                    Write-Host "`e[$($Targets.length+5)A"
                }

                # Output update delay
                Start-Sleep -Milliseconds $Update
            }

            # Clean up jobs
            If (!$killed) {
                $Targets.Job | Remove-Job -Force
            }

            # If in "Watch" mode, print output one last time
            If ($Watch) {
                $Targets.ToTable() | Format-Table
            }
        }
    }
} #End function