#変数関連
#--------------------------------------------------------------------------
#実行ファイルのパスを格納
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

#二重起動チェック
$mutex = New-Object System.Threading.Mutex($false, "Global¥MyPingCheck")
try
{
    if (-not $mutex.WaitOne(0, $false)) {
        $WS = New-Object -com Wscript.Shell
        $result = $WS.Popup("Ping監視は既に実行中です")
        $mutex.Close()
        exit
    }
}
catch [System.Threading.AbandonedMutexException]
{
    $WS = New-Object -com Wscript.Shell
    $result = $WS.Popup("前回の処理は強制終了しました。監視を再開します。")
}


#監視対象（ホスト名orIP）
$Hosts = [XML](Get-Content ($scriptPath + "\Hosts.xml"))

$Testhost = @()
$HostAliveCount =@()
$HostAliveFlag =@()
for($host_i=0;$host_i -lt $Hosts.Hosts.Host.Count;$host_i++){
    #Xmlから各ホストの情報を格納する
    $Testhost += $Hosts.Hosts.Host[$host_i]
    #各ホスト死活監視用カウントに０を代入する
    $HostAliveCount += 0
    #各ホスト死活監視フラグにTrueを代入する
    $HostAliveFlag += $True
    }

$Config = [XML](Get-Content ($scriptPath + "\Config.xml"))
#一度のPingでチェックする回数
    $PingCount = $Config.CONFIGS.CONFIG[0].Value
#Pingチェックが何回連続で失敗したら発報するか
    $MaxAlive = $Config.CONFIGS.CONFIG[1].Value
#Sleep時間(秒)
    $SleepTime = $Config.CONFIGS.CONFIG[2].Value
#PateliteIPアドレス
    $PateliteIPAdd = $Config.CONFIGS.CONFIG[3].Value
#Patelite発報アドレス
    $PateliteCole = $Config.CONFIGS.CONFIG[4].Value
#Pateliteコマンド(点灯)
　　$PateliteCommand = "http://" + $PateliteIPAdd + "/api/control?alert=" + $PateliteCole
#Pateliteコマンド（消灯）
　　$PateliteCommandClr = "http://" + $PateliteIPAdd + "/api/control?clear=1"


#--------------------------------------------------------------------------

#実行部分
#--------------------------------------------------------------------------
$WS = New-Object -com Wscript.Shell
$result = $WS.Popup("Ping監視を開始します")

while(1){
    for($j=0;$j -lt $Testhost.Count; $j++){
        #ping送付実施
        $pingAlive = @(Test-Connection $Testhost[$j] -Quiet -Count $PingCount)
            #ping応答がある場合
            if($pingAlive -eq $True){
                $HostAliveCount[$j] = 0
                if($HostAliveFlag[$j] -eq $True){
                    $now = Get-Date -Format G
                    Write-Output($now + " " + $Testhost[$j] + " is alive")
                #今まで死んでいたホストが立ち上がってきた場合
                }else{
                    $HostAliveFlag[$j] = $True
                    $now = Get-Date -Format G
                    Write-Output($now + " " + $Testhost[$j] + " is recovered") 
                    Write-Output ($now + " " + $Testhost[$j] + " is recovered") | Out-File -Append -Force ($scriptpath + "\log.txt")

                    #パトライト消灯
                    $PateliteFlagClr = (Invoke-WebRequest $PateliteCommandClr).Content
                    if ($PateliteFlag -eq "Success."){
                        Write-Output ($now + " " + " patelite's nortification clear") | Out-File -Append -Force ($scriptpath + "\log.txt")
                    }else{
                        Write-Output ($now + " " + " patelite's nortification clear false") | Out-File -Append -Force ($scriptpath + "\log.txt")
                    }
                    
                }
            #ping応答がない場合
            }else{
                $HostAliveCount[$j] = $HostAliveCount[$j] + 1
                if($HostAliveFlag[$j] -eq $True){
                    $now = Get-Date -Format G
                    Write-Output($now + " " + $Testhost[$j] + " is not reachable")
                }else{
                    #何もしない。何かする場合はここに書く。
                }
            }
        #ping応答無し状態が$MaxAliveの回数を上回った場合、発報する
        if ($HostAliveCount[$j] -ge $MaxAlive){
            if($HostAliveFlag[$j] -eq $True){
                $HostAliveFlag[$j] = $False
                $now = Get-Date -Format G
                Write-Output($now + " " + $Testhost[$j] + " is dead") 
                Write-Output ($now + " " + $Testhost[$j] + " is dead")  | Out-File -Append -Force ($scriptpath + "\log.txt")
                #パトライト発報
                $PateliteFlag =  (Invoke-WebRequest $PateliteCommand).Content
                if ($PateliteFlag -eq "Success."){
                    Write-Output ($now + " " + " patelite's nortification start") | Out-File -Append -Force ($scriptpath + "\log.txt")
                }else{
                    Write-Output ($now + " " + " patelite's nortification false") | Out-File -Append -Force ($scriptpath + "\log.txt")
                }

            }else{
                #今は一度死ぬと何もしないが、定期的に何か実施する場合はここに入力。
                #何もしない
            }
        }
    }

#指定時間一時停止
Start-Sleep -s $SleepTime
}
