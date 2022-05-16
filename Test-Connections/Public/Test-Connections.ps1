class Target {
    [String]$TargetName
    [String]$DNS
    hidden [PSObject]$Job
    [Int]$PingCount
    [boolean]$Status
    [Int]$Latency
    [Int]$LatencySum
    [Int]$SuccessSum

    Target() {}
    Target([String]$TargetName,[PSObject]$Job){
        $this.TargetName = $TargetName
        $this.Job = $Job
        $this.PingCount = 0
        $this.Status = $null
        $this.Latency = 0
        $this.LatencySum = 0
        $this.SuccessSum = 0
    }

    [String]ToString() {
        Return ("[{0}] {1} {2}ms {3:0.0}ms (avg) {4} {5:0.0}%" -f $this.Status, $this.TargetName, $this.Latency, $this.AverageLatency(), $this.PingCount, $this.PercentSuccess() )
    }

    [PSCustomObject]ToTable() {
        $e = [char]27
        If ($this.Status) {
            $s = "${e}[92mOKAY${e}[0m"
        } else {
            $s = "${e}[91mFAIL${e}[0m"
        }
        Return [PSCustomObject]@{
            Status = $s
            TargetName = $this.TargetName
            ms = $this.Latency
            Avg = [math]::Round($this.AverageLatency(),1)
            Count = $this.PingCount
            Loss = $this.PingCount - $this.SuccessSum
            Success = [math]::Round($this.PercentSuccess(),1)
        }
    }

    [void]Update([Object]$Update) {
        $last = $Update | Select-Object -Last 1
        $this.PingCount=$last.Ping
        $this.Status=$last.Status -eq "Success"
        $this.Latency=$last.Latency
        $this.LatencySum+=($Update.Latency | Measure-Object -Sum).Sum
        $this.SuccessSum+=($Update.Status | Where-Object {$_ -eq "Success"} | Measure-Object).Count
    }

    [int]Count() {
        Return $this.PingCount
    }

    [float]PercentSuccess() {
        If (! $this.PingCount -eq 0) {
            Return $this.SuccessSum / $this.PingCount * 100
        }
        Return 0
    }

    [float]AverageLatency() {
        If (! $this.SuccessSum -eq 0) {
            Return $this.LatencySum / $this.SuccessSum
        }
        Return 0
    }

}

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
            [int]$Update=1000
        )
        Begin {
            Write-Verbose -Message "Begin $($MyInvocation.MyCommand)"
            $Targets = @()
        }
        Process {
            Write-Verbose -Message "Process $($MyInvocation.MyCommand)"
            If ($pscmdlet.ShouldProcess("$TargetName")) {
                Write-Verbose -Message "Pinging $TargetName"
                If ($Repeat) {
                    $Targets += [Target]::new($TargetName,(Start-Job -ScriptBlock {Param ($TargetName) Test-Connection -TargetName $TargetName -Ping -Repeat} -ArgumentList $TargetName))
                } else {
                    $Targets += [Target]::new($TargetName,(Start-Job -ScriptBlock {Param ($TargetName) Test-Connection -TargetName $TargetName -Ping} -ArgumentList $TargetName))
                }
            }
            else {
                Write-Host "Not Pinging $TargetName"
            }
        }
        End {
            Write-Verbose -Message "End $($MyInvocation.MyCommand)"

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
                ForEach ($Target in $Targets) {
                    $Data=Receive-Job -Id $Target.Job.Id

                    If ($Data.ping -gt $Target.PingCount) {
                        $Target.Update($Data)
                    }
                }
                # Print Output
                Write-Host "====== $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") ======"
                $Targets.ToTable() | Format-Table
                Start-Sleep -Milliseconds $Update
            }

            If (!$killed) {
                $Targets.Job | Remove-Job -Force
            }

        }
    } #End function