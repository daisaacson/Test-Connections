function Test-Connections {
    <#
    .Synopsis
        Test-Connection to multiple devices.
    .Description
        Test-Connection to multiple devcies.
    .Example
        Test-Connections -TargetName 8.8.8.8
        
        Ping 8.8.8.8
    .Example
        Test-Connections 8.8.8.8

        Test-Connections
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
        note
    #Requires -Version 2.0
    #>
    [CmdletBinding(SupportsShouldProcess=$True)]
        Param
        (
            [Parameter(Mandatory=$True,ValueFromPipeline=$True,HelpMessage="Stop after sending Count pings")]
            [string[]]$TargetName,

            [Parameter(Mandatory=$False)]
            [Alias("c")]
            [int]$Count=4,

            [Parameter(Mandatory=$False,HelpMessage="Continjously send pings")]
            [Alias("Continuous","t")]
            [switch]$Repeat,

            [Parameter(Mandatory=$False,HelpMessage="Interval between pings")]
            [Alias("u")]
            [int]$Update=1000,

            [Parameter(Mandatory=$False,HelpMessage="Watch")]
            [Alias("w")]
            [Switch]$Watch=$False
        )
        Begin {
            Write-Verbose -Message "Begin $($MyInvocation.MyCommand)"
            $Targets = @()
        }
        Process {
            Write-Verbose -Message "Process $($MyInvocation.MyCommand)"
            If ($pscmdlet.ShouldProcess("$TargetName")) {
                ForEach ($Target in $TargetName) {
                    Write-Verbose -Message "Pinging $Target"
                    If ($Repeat) {
                        $Targets += [Target]::new($Target,(Start-Job -ScriptBlock {Param ($Target) Test-Connection -TargetName $Target -Ping -Repeat} -ArgumentList $Target))
                    } else {
                        $Targets += [Target]::new($Target,(Start-Job -ScriptBlock {Param ($Target) Test-Connection -TargetName $Target -Ping} -ArgumentList $Target))
                    }
                }
            }
        }
        End {
            Write-Verbose -Message "End $($MyInvocation.MyCommand)"
            If ($pscmdlet.ShouldProcess("$TargetName")) {
                # https://blog.sheehans.org/2018/10/27/powershell-taking-control-over-ctrl-c/
                # Change the default behavior of CTRL-C so that the script can intercept and use it versus just terminating the script.
                [Console]::TreatControlCAsInput=$True
                # Sleep for 1 second and then flush the key buffer so any previously pressed keys are discarded and the loop can monitor for the use of
                #   CTRL-C. The sleep command ensures the buffer flushes correctly.
                Start-Sleep -Seconds 1
                $Host.UI.RawUI.FlushInputBuffer()
                # Continue to loop while there are pending or currently executing jobs.
                While ($Targets.Job.HasMoreData -contains "True") {
                    # If a key was pressed during the loop execution, check to see if it was CTRL-C (aka "3"), and if so exit the script after clearing
                    #   out any running jobs and setting CTRL-C back to normal.
                    If ($Host.UI.RawUI.KeyAvailable -and ($Key=$Host.UI.RawUI.ReadKey("AllowCtrlC,NoEcho,IncludeKeyUp"))) {
                        If ([Int]$Key.Character -eq 3) {
                            Write-Host ""
                            Write-Warning -Message "Removing Test-Connection Jobs"
                            $Targets.Job | Remove-Job -Force
                            $killed = $True
                            [Console]::TreatControlCAsInput=$False

                            break
                        }
                        # Flush the key buffer again for the next loop.
                        $Host.UI.RawUI.FlushInputBuffer()
                    }
                    # Perform other work here such as process pending jobs or process out current jobs.
                    $Targets.Update()

                    # Print Output
                    Write-Host "====== $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") ======"
                    $Targets.ToTable() | Format-Table

                    # 
                    If ($Watch) {
                        Write-Host "`e[$($Targets.length+6)A"
                    }
                    Start-Sleep -Milliseconds $Update
                }

                If (!$killed) {
                    $Targets.Job | Remove-Job -Force
                }

                # If in "Watch" mode, print output one last time
                If ($Watch) {
                    #Write-Host "====== $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") ======"
                    If ($Repeat) { Write-Host "`e[1A" }
                    $Targets.ToTable() | Format-Table
                }
            }
        }
    } #End function