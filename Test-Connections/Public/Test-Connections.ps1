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
            [Parameter(Mandatory=$True,ValueFromPipeline=$True,HelpMessage="Enter a help message")]
            [string[]]$TargetName,
            [Parameter(Mandatory=$False)]
            [int]$Count,

            [Parameter(Mandatory=$False)]
            [Alias("Continuous")]
            [switch]$Repeat
        )
        Begin {
            Write-Verbose "Begin $($MyInvocation.MyCommand)"
            $Targets = @()
        }
        Process {
            Write-Verbose "Process $($MyInvocation.MyCommand)"
            If ($pscmdlet.ShouldProcess("$TargetName")) {
                Write-Host "Pinging $TargetName"
                If ($Repeat) {
                    $Targets+=[PSCustomObject]@{
                        Target=$TargetName
                        Job=Start-Job -ScriptBlock {Param ($TargetName) Test-Connection -TargetName $TargetName -Ping -Repeat} -ArgumentList $TargetName
                        Ping=0
                        Status=$null
                        Latency=0
                        LatencySum=0
                        SuccessSum=0
                    }
                }
            }
            else {
                Write-Host "Not Pinging $TargetName"
            }
        }
        End {
            Write-Verbose "End $($MyInvocation.MyCommand)"
            If ($Repeat) {
                # https://blog.sheehans.org/2018/10/27/powershell-taking-control-over-ctrl-c/
                # Change the default behavior of CTRL-C so that the script can intercept and use it versus just terminating the script.
                [Console]::TreatControlCAsInput=$True
                # Sleep for 1 second and then flush the key buffer so any previously pressed keys are discarded and the loop can monitor for the use of
                #   CTRL-C. The sleep command ensures the buffer flushes correctly.
                Start-Sleep -Seconds 1
                $Host.UI.RawUI.FlushInputBuffer()

                # Continue to loop while there are pending or currently executing jobs.
                While ($Targets.Job.State -contains "Running") {
                    # If a key was pressed during the loop execution, check to see if it was CTRL-C (aka "3"), and if so exit the script after clearing
                    #   out any running jobs and setting CTRL-C back to normal.
                    If ($Host.UI.RawUI.KeyAvailable -and ($Key=$Host.UI.RawUI.ReadKey("AllowCtrlC,NoEcho,IncludeKeyUp"))) {
                        If ([Int]$Key.Character -eq 3) {
                            Write-Host ""
                            Write-Warning -Message "Removing Test-Connection Jobs"
                            $Targets.Job | Remove-Job -Force
                            [Console]::TreatControlCAsInput=$False
                        }
                        # Flush the key buffer again for the next loop.
                        $Host.UI.RawUI.FlushInputBuffer()
                        Break
                    }

                    # Perform other work here such as process pending jobs or process out current jobs.
                    ForEach ($Target in $Targets) {
                        $temp=Receive-Job -Id $Target.Job.Id
                        If ($temp.ping -gt $Target.Ping) {
                            $Target.Ping=$temp.Ping | Select-Object -Last 1
                            $Target.Status=$temp.Status | Select-Object -Last 1
                            $Target.Latency=$temp.Latency | Select-Object -Last 1
                            $Target.LatencySum+=($temp.Latency | Measure-Object -Sum).Sum
                            $Target.SuccessSum+=($temp.Status | Where-Object {$_ -eq "Success"} | Measure-Object).Count
                        }
                        $Target
                    }
                    

                    Start-Sleep -Seconds 1
                }
            }
        }
    } #End function