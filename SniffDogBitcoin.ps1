﻿param(
    [Parameter(Mandatory=$false)]
    [String]$Wallet, 
    [Parameter(Mandatory=$false)]
    [String]$UserName = "Tyredas", 
    [Parameter(Mandatory=$false)]
    [String]$WorkerName = "Beeboop",
    [Parameter(Mandatory=$false)]
    [String]$RigName = "Sniffdog",
    [Parameter(Mandatory=$false)]
    [Int]$API_ID = 0, 
    [Parameter(Mandatory=$false)]
    [String]$API_Key = "", 
    [Parameter(Mandatory=$false)]
    [Int]$Interval = 90, #seconds before reading hash rate from miners
    [Parameter(Mandatory=$false)] 
    [Int]$StatsInterval = $null, #seconds of current active to gather hashrate if not gathered yet 
    [Parameter(Mandatory=$false)]
    [String]$Location = "US", #europe/us/asia
    [Parameter(Mandatory=$false)]
    [String]$MPHLocation = "US", #europe/us/asia
    [Parameter(Mandatory=$false)]
    [Switch]$SSL = $false, 
    [Parameter(Mandatory=$false)]
    [Array]$Type = $null, #AMD/NVIDIA/CPU
    [Parameter(Mandatory=$false)]
    [Array]$Algorithm = $null, #i.e. Ethash,Equihash,Cryptonight ect.
    [Parameter(Mandatory=$false)]
    [Array]$MinerName = $null,
    [Parameter(Mandatory=$false)] 
    [String]$SplitSniffEWBF = "0", 
    [Parameter(Mandatory=$false)] 
    [String]$SplitSniffCC = "0",
    [Parameter(Mandatory=$false)]
    [Array]$PoolName = $null, 
    [Parameter(Mandatory=$false)]
    [Array]$Currency = ("USD"), #i.e. GBP,EUR,ZEC,ETH ect.
    [Parameter(Mandatory=$false)]
    [Array]$Passwordcurrency = ("BTC"), #i.e. BTC,LTC,ZEC,ETH ect.
    [Parameter(Mandatory=$false)]
    [Int]$Donate = 5, #Minutes per Day
    [Parameter(Mandatory=$false)]
    [String]$Proxy = "", #i.e http://192.0.0.1:8080 
    [Parameter(Mandatory=$false)]
    [Int]$Delay = 1 #seconds before opening each miner
)

Set-Location (Split-Path $script:MyInvocation.MyCommand.Path)

Get-ChildItem . -Recurse | Unblock-File
try{if((Get-MpPreference).ExclusionPath -notcontains (Convert-Path .)){Start-Process powershell -Verb runAs -ArgumentList "Add-MpPreference -ExclusionPath '$(Convert-Path .)'"}}catch{}

if($Proxy -eq ""){$PSDefaultParameterValues.Remove("*:Proxy")}
else{$PSDefaultParameterValues["*:Proxy"] = $Proxy}

. .\Include.ps1

$DecayStart = Get-Date
$DecayPeriod = 60 #seconds
$DecayBase = 1-0.1 #decimal percentage

$ActiveMinerPrograms = @()

#Start the log
Start-Transcript ".\Logs\$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").txt"

#Update stats with missing data and set to today's date/time
if(Test-Path "Stats"){Get-ChildItemContent "Stats" | ForEach {$Stat = Set-Stat $_.Name $_.Content.Week}}

#Set donation parameters
$LastDonated = (Get-Date).AddDays(-1).AddHours(1)
$WalletDonate = "1AMQg6m9GPDN9HGuC3wJGpSuiZr1XQXjxi"
$UserNameDonate = "Tyredas"
$WorkerNameDonate = "Beeboop"
$WalletBackup = $Wallet
$UserNameBackup = $UserName
$WorkerNameBackup = $WorkerName

while($true)
{
    $DecayExponent = [int](((Get-Date)-$DecayStart).TotalSeconds/$DecayPeriod)

    #Activate or deactivate donation
    if((Get-Date).AddDays(-1).AddMinutes($Donate) -ge $LastDonated)
    {
        $Wallet = $WalletDonate
        $UserName = $UserNameDonate
        $WorkerName = $WorkerNameDonate
    }
    if((Get-Date).AddDays(-1) -ge $LastDonated)
    {
        $Wallet = $WalletBackup
        $UserName = $UserNameBackup
        $WorkerName = $WorkerNameBackup
        $LastDonated = Get-Date
    }
    try {
        Write-Host "SniffDog dumps then checks for updates from Coinbase..." -foregroundcolor "Yellow"
        $Rates = Invoke-RestMethod "https://api.coinbase.com/v2/exchange-rates?currency=BTC" -UseBasicParsing | Select-Object -ExpandProperty data | Select-Object -ExpandProperty rates
        $Currency | Where-Object {$Rates.$_} | ForEach-Object {$Rates | Add-Member $_ ([Double]$Rates.$_) -Force}
    }
    catch {
    Write-Host -Level Warn "Pee's on Coinbase. "

    Write-Host -ForegroundColor Yellow "Last Refresh: $(Get-Date)"
    Write-host "tries Sniffin at Cryptonator.." -foregroundcolor "Yellow"
        $Rates = [PSCustomObject]@{}
        $Currency | ForEach {$Rates | Add-Member $_ (Invoke-WebRequest "https://api.cryptonator.com/api/ticker/btc-$_" -UseBasicParsing | ConvertFrom-Json).ticker.price}
   }
    #Load the Stats
    $Stats = [PSCustomObject]@{}
    if(Test-Path "Stats"){Get-ChildItemContent "Stats" | ForEach {$Stats | Add-Member $_.Name $_.Content}}

    #Load information about the Pools
    $AllPools = if(Test-Path "Pools"){Get-ChildItemContent "Pools" | ForEach {$_.Content | Add-Member @{Name = $_.Name} -PassThru} | 
        Where Location -EQ $Location | 
        Where SSL -EQ $SSL | 
        Where {$PoolName.Count -eq 0 -or (Compare $PoolName $_.Name -IncludeEqual -ExcludeDifferent | Measure).Count -gt 0}}
    if($AllPools.Count -eq 0){"No Pools!" | Out-Host; sleep $Interval; continue}
    $Pools = [PSCustomObject]@{}
    $Pools_Comparison = [PSCustomObject]@{}
    $AllPools.Algorithm | Select -Unique | ForEach {$Pools | Add-Member $_ ($AllPools | Where Algorithm -EQ $_ | Sort Price -Descending | Select -First 1)}
    $AllPools.Algorithm | Select -Unique | ForEach {$Pools_Comparison | Add-Member $_ ($AllPools | Where Algorithm -EQ $_ | Sort StablePrice -Descending | Select -First 1)}

    #Load information about the Miners
    #Messy...?
    $Miners = if(Test-Path "Miners"){Get-ChildItemContent "Miners" | ForEach {$_.Content | Add-Member @{Name = $_.Name} -PassThru} | 
        Where {$Type.Count -eq 0 -or (Compare $Type $_.Type -IncludeEqual -ExcludeDifferent | Measure).Count -gt 0} | 
        Where {$Algorithm.Count -eq 0 -or (Compare $Algorithm $_.HashRates.PSObject.Properties.Name -IncludeEqual -ExcludeDifferent | Measure).Count -gt 0} | 
        Where {$MinerName.Count -eq 0 -or (Compare $MinerName $_.Name -IncludeEqual -ExcludeDifferent | Measure).Count -gt 0}}
    $Miners = $Miners | ForEach {
        $Miner = $_
        if((Test-Path $Miner.Path) -eq $false)
        {
            if((Split-Path $Miner.URI -Leaf) -eq (Split-Path $Miner.Path -Leaf))
            {
                New-Item (Split-Path $Miner.Path) -ItemType "Directory" | Out-Null
                Invoke-WebRequest $Miner.URI -OutFile $_.Path -UseBasicParsing
            }
            elseif(([IO.FileInfo](Split-Path $_.URI -Leaf)).Extension -eq '')
            {
                $Path_Old = Get-PSDrive -PSProvider FileSystem | ForEach {Get-ChildItem -Path $_.Root -Include (Split-Path $Miner.Path -Leaf) -Recurse -ErrorAction Ignore} | Sort LastWriteTimeUtc -Descending | Select -First 1
                $Path_New = $Miner.Path

                if($Path_Old -ne $null)
                {
                    if(Test-Path (Split-Path $Path_New)){(Split-Path $Path_New) | Remove-Item -Recurse -Force}
                    (Split-Path $Path_Old) | Copy-Item -Destination (Split-Path $Path_New) -Recurse -Force
                }
                else
                {
                    Write-Host -BackgroundColor Yellow -ForegroundColor Black "Cannot find $($Miner.Path) distributed at $($Miner.URI). "
                }
            }
            else
            {
                Expand-WebRequest $Miner.URI (Split-Path $Miner.Path)
            }
        }
        else
        {
            $Miner
        }
    }
    if($Miners.Count -eq 0){"No Miners!" | Out-Host; sleep $Interval; continue}
    $Miners | ForEach {
        $Miner = $_

        $Miner_HashRates = [PSCustomObject]@{}
        $Miner_Pools = [PSCustomObject]@{}
        $Miner_Pools_Comparison = [PSCustomObject]@{}
        $Miner_Profits = [PSCustomObject]@{}
        $Miner_Profits_Comparison = [PSCustomObject]@{}
        $Miner_Profits_Bias = [PSCustomObject]@{}

        $Miner_Types = $Miner.Type | Select -Unique
        $Miner_Indexes = $Miner.Index | Select -Unique

        $Miner.HashRates | Get-Member -MemberType NoteProperty | Select -ExpandProperty Name | ForEach {
            $Miner_HashRates | Add-Member $_ ([Double]$Miner.HashRates.$_)
            $Miner_Pools | Add-Member $_ ([PSCustomObject]$Pools.$_)
            $Miner_Pools_Comparison | Add-Member $_ ([PSCustomObject]$Pools_Comparison.$_)
            $Miner_Profits | Add-Member $_ ([Double]$Miner.HashRates.$_*$Pools.$_.Price)
            $Miner_Profits_Comparison | Add-Member $_ ([Double]$Miner.HashRates.$_*$Pools_Comparison.$_.Price)
            $Miner_Profits_Bias | Add-Member $_ ([Double]$Miner.HashRates.$_*$Pools.$_.Price*(1-($Pools.$_.MarginOfError*[Math]::Pow($DecayBase,$DecayExponent))))
        }
        
        $Miner_Profit = [Double]($Miner_Profits.PSObject.Properties.Value | Measure -Sum).Sum
        $Miner_Profit_Comparison = [Double]($Miner_Profits_Comparison.PSObject.Properties.Value | Measure -Sum).Sum
        $Miner_Profit_Bias = [Double]($Miner_Profits_Bias.PSObject.Properties.Value | Measure -Sum).Sum
        
        $Miner.HashRates | Get-Member -MemberType NoteProperty | Select -ExpandProperty Name | ForEach {
            if(-not [String]$Miner.HashRates.$_)
            {
                $Miner_HashRates.$_ = $null
                $Miner_Profits.$_ = $null
                $Miner_Profits_Comparison.$_ = $null
                $Miner_Profits_Bias.$_ = $null
                $Miner_Profit = $null
                $Miner_Profit_Comparison = $null
                $Miner_Profit_Bias = $null
            }
        }

        if($Miner_Types -eq $null){$Miner_Types = $Miners.Type | Select -Unique}
        if($Miner_Indexes -eq $null){$Miner_Indexes = $Miners.Index | Select -Unique}
        
        if($Miner_Types -eq $null){$Miner_Types = ""}
        if($Miner_Indexes -eq $null){$Miner_Indexes = 0}
        
        $Miner.HashRates = $Miner_HashRates

        $Miner | Add-Member Pools $Miner_Pools
        $Miner | Add-Member Profits $Miner_Profits
        $Miner | Add-Member Profits_Comparison $Miner_Profits_Comparison
        $Miner | Add-Member Profits_Bias $Miner_Profits_Bias
        $Miner | Add-Member Profit $Miner_Profit
        $Miner | Add-Member Profit_Comparison $Miner_Profit_Comparison
        $Miner | Add-Member Profit_Bias $Miner_Profit_Bias
        
        $Miner | Add-Member Type $Miner_Types -Force
        $Miner | Add-Member Index $Miner_Indexes -Force

        $Miner.Path = Convert-Path $Miner.Path
    }
    $Miners | ForEach {
        $Miner = $_
        $Miner_Devices = $Miner.Device | Select -Unique
        if($Miner_Devices -eq $null){$Miner_Devices = ($Miners | Where {(Compare $Miner.Type $_.Type -IncludeEqual -ExcludeDifferent | Measure).Count -gt 0}).Device | Select -Unique}
        if($Miner_Devices -eq $null){$Miner_Devices = $Miner.Type}
        $Miner | Add-Member Device $Miner_Devices -Force
    }

    #Don't penalize active miners
    $ActiveMinerPrograms | ForEach {$Miners | Where Path -EQ $_.Path | Where Arguments -EQ $_.Arguments | ForEach {$_.Profit_Bias = $_.Profit}}

    #Get most profitable miner combination i.e. AMD+NVIDIA+CPU
    $BestMiners = $Miners | Select Type,Index -Unique | ForEach {$Miner_GPU = $_; ($Miners | Where {(Compare $Miner_GPU.Type $_.Type | Measure).Count -eq 0 -and (Compare $Miner_GPU.Index $_.Index | Measure).Count -eq 0} | Sort -Descending {($_ | Where Profit -EQ $null | Measure).Count},{($_ | Measure Profit_Bias -Sum).Sum},{($_ | Where Profit -NE 0 | Measure).Count} | Select -First 1)}
    $BestDeviceMiners = $Miners | Select Device -Unique | ForEach {$Miner_GPU = $_; ($Miners | Where {(Compare $Miner_GPU.Device $_.Device | Measure).Count -eq 0} | Sort -Descending {($_ | Where Profit -EQ $null | Measure).Count},{($_ | Measure Profit_Bias -Sum).Sum},{($_ | Where Profit -NE 0 | Measure).Count} | Select -First 1)}
    $BestMiners_Comparison = $Miners | Select Type,Index -Unique | ForEach {$Miner_GPU = $_; ($Miners | Where {(Compare $Miner_GPU.Type $_.Type | Measure).Count -eq 0 -and (Compare $Miner_GPU.Index $_.Index | Measure).Count -eq 0} | Sort -Descending {($_ | Where Profit -EQ $null | Measure).Count},{($_ | Measure Profit_Comparison -Sum).Sum},{($_ | Where Profit -NE 0 | Measure).Count} | Select -First 1)}
    $BestDeviceMiners_Comparison = $Miners | Select Device -Unique | ForEach {$Miner_GPU = $_; ($Miners | Where {(Compare $Miner_GPU.Device $_.Device | Measure).Count -eq 0} | Sort -Descending {($_ | Where Profit -EQ $null | Measure).Count},{($_ | Measure Profit_Comparison -Sum).Sum},{($_ | Where Profit -NE 0 | Measure).Count} | Select -First 1)}
    $Miners_Type_Combos = @([PSCustomObject]@{Combination = @()}) + (Get-Combination ($Miners | Select Type -Unique) | Where{(Compare ($_.Combination | Select -ExpandProperty Type -Unique) ($_.Combination | Select -ExpandProperty Type) | Measure).Count -eq 0})
    $Miners_Index_Combos = @([PSCustomObject]@{Combination = @()}) + (Get-Combination ($Miners | Select Index -Unique) | Where{(Compare ($_.Combination | Select -ExpandProperty Index -Unique) ($_.Combination | Select -ExpandProperty Index) | Measure).Count -eq 0})
    $Miners_Device_Combos = (Get-Combination ($Miners | Select Device -Unique) | Where{(Compare ($_.Combination | Select -ExpandProperty Device -Unique) ($_.Combination | Select -ExpandProperty Device) | Measure).Count -eq 0})
    $BestMiners_Combos = $Miners_Type_Combos | ForEach {$Miner_Type_Combo = $_.Combination; $Miners_Index_Combos | ForEach {$Miner_Index_Combo = $_.Combination; [PSCustomObject]@{Combination = $Miner_Type_Combo | ForEach {$Miner_Type_Count = $_.Type.Count; [Regex]$Miner_Type_Regex = ‘^(‘ + (($_.Type | ForEach {[Regex]::Escape($_)}) -join “|”) + ‘)$’; $Miner_Index_Combo | ForEach {$Miner_Index_Count = $_.Index.Count; [Regex]$Miner_Index_Regex = ‘^(‘ + (($_.Index | ForEach {[Regex]::Escape($_)}) –join “|”) + ‘)$’; $BestMiners | Where {([Array]$_.Type -notmatch $Miner_Type_Regex).Count -eq 0 -and ([Array]$_.Index -notmatch $Miner_Index_Regex).Count -eq 0 -and ([Array]$_.Type -match $Miner_Type_Regex).Count -eq $Miner_Type_Count -and ([Array]$_.Index -match $Miner_Index_Regex).Count -eq $Miner_Index_Count}}}}}}
    $BestMiners_Combos += $Miners_Device_Combos | ForEach {$Miner_Device_Combo = $_.Combination; [PSCustomObject]@{Combination = $Miner_Device_Combo | ForEach {$Miner_Device_Count = $_.Device.Count; [Regex]$Miner_Device_Regex = ‘^(‘ + (($_.Device | ForEach {[Regex]::Escape($_)}) -join “|”) + ‘)$’; $BestDeviceMiners | Where {([Array]$_.Device -notmatch $Miner_Device_Regex).Count -eq 0 -and ([Array]$_.Device -match $Miner_Device_Regex).Count -eq $Miner_Device_Count}}}}
    $BestMiners_Combos_Comparison = $Miners_Type_Combos | ForEach {$Miner_Type_Combo = $_.Combination; $Miners_Index_Combos | ForEach {$Miner_Index_Combo = $_.Combination; [PSCustomObject]@{Combination = $Miner_Type_Combo | ForEach {$Miner_Type_Count = $_.Type.Count; [Regex]$Miner_Type_Regex = ‘^(‘ + (($_.Type | ForEach {[Regex]::Escape($_)}) -join “|”) + ‘)$’; $Miner_Index_Combo | ForEach {$Miner_Index_Count = $_.Index.Count; [Regex]$Miner_Index_Regex = ‘^(‘ + (($_.Index | ForEach {[Regex]::Escape($_)}) –join “|”) + ‘)$’; $BestMiners_Comparison | Where {([Array]$_.Type -notmatch $Miner_Type_Regex).Count -eq 0 -and ([Array]$_.Index -notmatch $Miner_Index_Regex).Count -eq 0 -and ([Array]$_.Type -match $Miner_Type_Regex).Count -eq $Miner_Type_Count -and ([Array]$_.Index -match $Miner_Index_Regex).Count -eq $Miner_Index_Count}}}}}}
    $BestMiners_Combos_Comparison += $Miners_Device_Combos | ForEach {$Miner_Device_Combo = $_.Combination; [PSCustomObject]@{Combination = $Miner_Device_Combo | ForEach {$Miner_Device_Count = $_.Device.Count; [Regex]$Miner_Device_Regex = ‘^(‘ + (($_.Device | ForEach {[Regex]::Escape($_)}) -join “|”) + ‘)$’; $BestDeviceMiners_Comparison | Where {([Array]$_.Device -notmatch $Miner_Device_Regex).Count -eq 0 -and ([Array]$_.Device -match $Miner_Device_Regex).Count -eq $Miner_Device_Count}}}}
    $BestMiners_Combo = $BestMiners_Combos | Sort -Descending {($_.Combination | Where Profit -EQ $null | Measure).Count},{($_.Combination | Measure Profit_Bias -Sum).Sum},{($_.Combination | Where Profit -NE 0 | Measure).Count} | Select -First 1 | Select -ExpandProperty Combination
    $BestMiners_Combo_Comparison = $BestMiners_Combos_Comparison | Sort -Descending {($_.Combination | Where Profit -EQ $null | Measure).Count},{($_.Combination | Measure Profit_Comparison -Sum).Sum},{($_.Combination | Where Profit -NE 0 | Measure).Count} | Select -First 1 | Select -ExpandProperty Combination

    #Add the most profitable miners to the active list
    $BestMiners_Combo | ForEach {
        if(($ActiveMinerPrograms | Where Path -EQ $_.Path | Where Arguments -EQ $_.Arguments).Count -eq 0)
        {
            $ActiveMinerPrograms += [PSCustomObject]@{
                Name = $_.Name
                Path = $_.Path
                Arguments = $_.Arguments
                Wrap = $_.Wrap
                Process = $null
                API = $_.API
                Port = $_.Port
                Algorithms = $_.HashRates.PSObject.Properties.Name
                New = $false
                Active = [TimeSpan]0
                Activated = 0
                Failed30sLater = 0
                Recover30sLater = 0
                Status = "Idle"
                HashRate = 0
                Benchmarked = 0
                Hashrate_Gathered = ($_.HashRates.PSObject.Properties.Value -ne $null)
            }
        }
    }

    #Stop or start miners in the active list depending on if they are the most profitable
    $ActiveMinerPrograms | ForEach {
        if(($BestMiners_Combo | Where Path -EQ $_.Path | Where Arguments -EQ $_.Arguments).Count -eq 0)
        {
            if($_.Process -eq $null)
            {
                $_.Status = "Failed"
            }
            elseif($_.Process.HasExited -eq $false)
            {
                $_.Active += (Get-Date)-$_.Process.StartTime
                $_.Process.CloseMainWindow() | Out-Null
                $_.Status = "Idle"
            }
        }
        else
        {
            if($_.Process -eq $null -or $_.Process.HasExited -ne $false)
            {
                Sleep $Delay #Wait to prevent BSOD
                $DecayStart = Get-Date
                $_.New = $true
                $_.Activated++
                if($_.Wrap){$_.Process = Start-Process -FilePath "PowerShell" -ArgumentList "-executionpolicy bypass -command . '$(Convert-Path ".\Wrapper.ps1")' -ControllerProcessID $PID -Id '$($_.Port)' -FilePath '$($_.Path)' -ArgumentList '$($_.Arguments)' -WorkingDirectory '$(Split-Path $_.Path)'" -PassThru}
                else{$_.Process = Start-SubProcess -FilePath $_.Path -ArgumentList $_.Arguments -WorkingDirectory (Split-Path $_.Path)}
                if($_.Process -eq $null){$_.Status = "Failed"}
                else{$_.Status = "Running"}
            }
        }
    }
    
    #Display mining information
    Clear-Host
    #Display active miners list
    $ActiveMinerPrograms | Sort -Descending Status,{if($_.Process -eq $null){[DateTime]0}else{$_.Process.StartTime}} | Select -First (1+6+6) | Format-Table -Wrap -GroupBy Status (
        @{Label = "Speed"; Expression={$_.HashRate | ForEach {"$($_ | ConvertTo-Hash)/s"}}; Align='right'}, 
        @{Label = "Active"; Expression={"{0:dd} Days {0:hh} Hours {0:mm} Minutes" -f $(if($_.Process -eq $null){$_.Active}else{if($_.Process.HasExited){($_.Active)}else{($_.Active+((Get-Date)-$_.Process.StartTime))}})}}, 
        @{Label = "Launched"; Expression={Switch($_.Activated){0 {"Never"} 1 {"Once"} Default {"$_ Times"}}}}, 
        @{Label = "Command"; Expression={"$($_.Path.TrimStart((Convert-Path ".\"))) $($_.Arguments)"}}
    ) | Out-Host
        #Write-Host "..........Excavator is dormant in Sniffdog for Neoscrypt,Keccak,Lyra2rev2, and Nist5..............." -foregroundcolor "Green"
        #Write-Host "..........Remove # in front of Algo in ExcavatorNvidianeo.ps1 file in Miners Folder......................" -foregroundcolor "Green"  
        #Write-Host "................Then restart SniffDog and let Excavator Download to Bin Folder..........................." -foregroundcolor "Green"
        #Write-Host "................Shutdown SniffDog....Goto Bin Folder and to Excavator Folder............................." -foregroundcolor "Green"
        #Write-Host "...........Find Files and move back one folder so it's Bin\Excavator\excavator.exe......................." -foregroundcolor "Green"
        #Write-Host ""
        #Write-Host "..........All miners algos in Miners Folder can be opened by removing # or closed by adding a #.........." -foregroundcolor "Green"
        Write-Host ""
        Write-Host ""
        Write-Host ""
        Write-Host ""
        Write-Host ""
        Write-Host ""
        Write-Host ""
        Write-Host ""
        Write-Host ""
        Write-Host "                      Thank you Everyone For using SniffDog!!!!!" -foregroundcolor "Yellow"
        Write-Host ""
        Write-Host ""
        Write-Host ""
        Write-Host ""
     Write-Host "1BTC = " $Rates.$Currency "$Currency" -foregroundcolor "Yellow"
    $Miners | Where {$_.Profit -ge 1E-5 -or $_.Profit -eq $null} | Sort -Descending Type,Profit | Format-Table -GroupBy Type (
        @{Label = "Miner"; Expression={$_.Name}}, 
        @{Label = "Algorithm"; Expression={$_.HashRates.PSObject.Properties.Name}}, 
        @{Label = "Speed"; Expression={$_.HashRates.PSObject.Properties.Value | ForEach {if($_ -ne $null){"$($_ | ConvertTo-Hash)/s"}else{"Bench"}}}; Align='center'}, 
        @{Label = "BTC/Day"; Expression={$_.Profits.PSObject.Properties.Value | ForEach {if($_ -ne $null){  $_.ToString("N5")}else{"Bench"}}}; Align='right'}, 
        @{Label = "BTC/GH/Day"; Expression={$_.Pools.PSObject.Properties.Value.Price | ForEach {($_*1000000000).ToString("N5")}}; Align='center'},
        @{Label = "$Currency/Day"; Expression={$_.Profits.PSObject.Properties.Value | ForEach {if($_ -ne $null){($_ * $Rates.$Currency).ToString("N3")}else{"Bench"}}}; Align='center'}, 
        @{Label = "Pool"; Expression={$_.Pools.PSObject.Properties.Value | ForEach {"$($_.Name)"}}; Align='center'},
        @{Label = "Coins"; Expression={$_.Pools.PSObject.Properties.Value | ForEach {"  $($_.Info)"}}; Align='center'},
        @{Label = "Pool Fees"; Expression={$_.Pools.PSObject.Properties.Value | ForEach {"$($_.Fees)%"}}; Align='center'},
        @{Label = "# of Workers"; Expression={$_.Pools.PSObject.Properties.Value | ForEach {"$($_.Workers)"}}; Align='center'}
        
    ) | Out-Host
    

    #Display profit comparison
    if (($BestMiners_Combo | Where-Object Profit -EQ $null | Measure-Object).Count -eq 0) {
        $MinerComparisons = 
        [PSCustomObject]@{"Miner" = "Sniffdog.. sniffs out!"}, 
        [PSCustomObject]@{"Miner" = $BestMiners_Combo_Comparison | ForEach-Object {"$($_.Name)-$($_.Algorithm -join "/")"}}
            
        $BestMiners_Combo_Stat = Set-Stat -Name "Profit" -Value ($BestMiners_Combo | Measure-Object Profit -Sum).Sum

        $MinerComparisons_Profit = $BestMiners_Combo_Stat.Day, ($BestMiners_Combo_Comparison | Measure-Object Profit_Comparison -Sum).Sum

        $MinerComparisons_MarginOfError = $BestMiners_Combo_Stat.Day_Fluctuation, ($BestMiners_Combo_Comparison | ForEach-Object {$_.Profit_MarginOfError * (& {if ($MinerComparisons_Profit[1]) {$_.Profit_Comparison / $MinerComparisons_Profit[1]}else {1}})} | Measure-Object -Sum).Sum

        $Currency | ForEach-Object {
            $MinerComparisons[0] | Add-Member $_ ("{0:N5} ±{1:P0} ({2:N5}-{3:N5})" -f ($MinerComparisons_Profit[0] * $Rates.$_), $MinerComparisons_MarginOfError[0], (($MinerComparisons_Profit[0] * $Rates.$_) / (1 + $MinerComparisons_MarginOfError[0])), (($MinerComparisons_Profit[0] * $Rates.$_) * (1 + $MinerComparisons_MarginOfError[0])))
            $MinerComparisons[1] | Add-Member $_ ("{0:N5} ±{1:P0} ({2:N5}-{3:N5})" -f ($MinerComparisons_Profit[1] * $Rates.$_), $MinerComparisons_MarginOfError[1], (($MinerComparisons_Profit[1] * $Rates.$_) / (1 + $MinerComparisons_MarginOfError[1])), (($MinerComparisons_Profit[1] * $Rates.$_) * (1 + $MinerComparisons_MarginOfError[1])))
        }

        if ($MinerComparisons_Profit[0] -gt $MinerComparisons_Profit[1]) {
            $MinerComparisons_Range = ($MinerComparisons_MarginOfError | Measure-Object -Average | Select-Object -ExpandProperty Average), (($MinerComparisons_Profit[0] - $MinerComparisons_Profit[1]) / $MinerComparisons_Profit[1]) | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum
            Write-Host -BackgroundColor Yellow -ForegroundColor Black "SniffDog sniffs $([Math]::Round((((($MinerComparisons_Profit[0]-$MinerComparisons_Profit[1])/$MinerComparisons_Profit[1])-$MinerComparisons_Range)*100)))% and upto $([Math]::Round((((($MinerComparisons_Profit[0]-$MinerComparisons_Profit[1])/$MinerComparisons_Profit[1])+$MinerComparisons_Range)*100)))% more profit than the fastest (listed) miner: "
        }

        $MinerComparisons | Out-Host
    }


#Do nothing for 15 seconds, and check if ccminer is actually running
    $CheckMinerInterval = 15
    Sleep ($CheckMinerInterval)
    $ActiveMinerPrograms | ForEach {
        if($_.Process -eq $null -or $_.Process.HasExited)
        {
            if($_.Status -eq "Running"){
                $_.Failed30sLater++
                
                if($_.Wrap){$_.Process = Start-Process -FilePath "PowerShell" -ArgumentList "-executionpolicy bypass -command . '$(Convert-Path ".\Wrapper.ps1")' -ControllerProcessID $PID -Id '$($_.Port)' -FilePath '$($_.Path)' -ArgumentList '$($_.Arguments)' -WorkingDirectory '$(Split-Path $_.Path)'" -PassThru}
                else{$_.Process = Start-SubProcess -FilePath $_.Path -ArgumentList $_.Arguments -WorkingDirectory (Split-Path $_.Path)}
               
                Sleep ($CheckMinerInterval)
                if($_.Process -eq $null -or $_.Process.HasExited) {
                    continue
                } else {
                    $_.Recover30sLater++
                }
            }
        }
    }

     

    #You can examine the difference before and after with:
    ps powershell* | Select *memory* | ft -auto `
    @{Name='Virtual Memory Size (MB)';Expression={($_.VirtualMemorySize64)/1MB}; Align='center'}, `
    @{Name='Private Memory Size (MB)';Expression={(  $_.PrivateMemorySize64)/1MB}; Align='center'},
    @{Name='Memory Used This Session (MB)';Expression={([System.gc]::gettotalmemory("forcefullcollection") /1MB)}; Align='center'}

   


    #Reduce Memory
    Get-Job -State Completed | Remove-Job
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    [GC]::Collect()
    
    Write-Host "1BTC = " $Rates.$Currency "$Currency" -foregroundcolor "Yellow"

    #Do nothing for a set Interval to allow miner to run
    If ([int]$Interval -gt [int]$CheckMinerInterval) {
        Sleep ($Interval-$CheckMinerInterval)
    } else {
        Sleep ($Interval)
    }

     

    #Save current hash rates
    $ActiveMinerPrograms | ForEach {
        if($_.Process -eq $null -or $_.Process.HasExited)
        {
            if($_.Status -eq "Running"){$_.Status = "Failed"}
        }
        else
        {

            $WasActive = [math]::Round(((Get-Date)-$_.Process.StartTime).TotalSeconds) 
             if ($WasActive -ge $StatsInterval) {

            $_.HashRate = 0  
            $Miner_HashRates = $null  
   
            if($_.New){$_.Benchmarked++} 

            $Miner_HashRates = Get-HashRate $_.API $_.Port ($_.New -and $_.Benchmarked -lt 3)

            $_.HashRate = $Miner_HashRates | Select -First $_.Algorithms.Count
            
            if($Miner_HashRates.Count -ge $_.Algorithms.Count)
            {
                for($i = 0; $i -lt $_.Algorithms.Count; $i++)
                {
                    $Stat = Set-Stat -Name "$($_.Name)_$($_.Algorithms | Select -Index $i)_HashRate" -Value ($Miner_HashRates | Select -Index $i)
                }

                $_.New = $false
                $_.Hashrate_Gathered = $true 
                Write-Host "SniffDog chews on"$_.Algorithms" then saves hashrate" -foregroundcolor "Yellow"
            }
        }
    }

        #Benchmark timeout
        if($_.Benchmarked -ge 6 -or ($_.Benchmarked -ge 2 -and $_.Activated -ge 2))
        {
            for($i = 0; $i -lt $_.Algorithms.Count; $i++)
            {
                if((Get-Stat "$($_.Name)_$($_.Algorithms | Select -Index $i)_HashRate") -eq $null)
                {
                    $Stat = Set-Stat -Name "$($_.Name)_$($_.Algorithms | Select -Index $i)_HashRate" -Value 0
                }
            }
        }
        
    }
}

#Stop the log
Stop-Transcript
