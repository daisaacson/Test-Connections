class Target {
    [String]$TargetName
    [String]$DNS
    hidden [PSObject]$Job
    [Int]$PingCount
    [boolean]$Status
    [Int]$Latency
    [Int]$LatencySum
    [Int]$SuccessSum
    [DateTime]$LastSuccessTime

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
        if ($null -eq $this.status) {
            $s = "`e[1;38;5;0;48;5;226m PEND `e[0m"
        } elseif ($this.status) {
            $s = "`e[1;38;5;0;48;5;46m OKAY `e[0m"
        } else {
            $s = "`e[1;38;5;0;48;5;196m FAIL `e[0m"
        }
        Return [PSCustomObject]@{
            Status = $s
            TargetName = $this.TargetName
            ms = $this.Latency
            Avg = [math]::Round($this.AverageLatency(),1)
            Count = $this.PingCount
            Loss = $this.PingCount - $this.SuccessSum
            Success = [math]::Round($this.PercentSuccess(),1)
            LastSuccess = $this.LastSuccessTime
        }
    }

    [void]Update() {
        $Data=Receive-Job -Id $this.Job.Id

        # If data is newer than update attributes
        If ($Data.ping -gt $this.PingCount) {
            $last = $Data | Select-Object -Last 1
            $this.PingCount=$last.Ping
            $this.Status=$last.Status -eq "Success"
            $this.Latency=$last.Latency
            $this.LatencySum+=($Data.Latency | Measure-Object -Sum).Sum
            $this.SuccessSum+=($Data.Status | Where-Object {$_ -eq "Success"} | Measure-Object).Count
            if ($this.Status) {
                $this.LastSuccessTime = Get-Date
            }
        }
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