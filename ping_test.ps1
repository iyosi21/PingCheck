#--------------------------------------------------------------------------
#メッセージ表示関数（各ホストの死活状態表示、最新のステータスを２０行表示）
#--------------------------------------------------------------------------
function PMessage ($Testhost, $HostAliveCount, $HostAliveFlag, $MessageArray_arg, $scriptPath){
    Clear-Host
    echo "[host status]==========================="

    for($j=0;$j -lt $Testhost.Count; $j++){
        $pramhoshi=""
        for($k=0;$k -lt $HostAliveCount[$j]; $k++){
            $pramhoshi = $pramhoshi +"*"
        }
        if($HostAliveFlag -eq $True){
            $echoAlive = "is alive" + $pramhoshi
                }else{$echoAlive = "is dead"}

        echo($Testhost[$j] + " " + $echoAlive)
    }
    echo ""
    echo "[latest message]========================"

    foreach ($Messe in $MessageArray){
        echo $Messe
    }
    echo $MessageArray_arg[0] | Out-File -Append -Force ($scriptpath + "\log.txt")
}

#このfunctionで送られてきたメッセージに追加して、配列を返す
function LatestMessage($MessageArray, $Latest_stat){
    $tempArray = @()
    #最終的に表示できるログの表示はConfigで設定できるようにしたい
    for($j=0;$j -lt $MessageArray.Count; $j++){
        $tempArray += ""
    }
    for($j=1;$j -lt $MessageArray.Count; $j++){
        $tempArray[$j] = $MessageArray[$j - 1]
    }
    $tempArray[0] = $Latest_stat
    return $tempArray
}

#--------------------------------------------------------------------------
#メイン処理
#--------------------------------------------------------------------------
#実行ファイルのパスを格納
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

#--------------------------------------------------------------------------
#二重起動チェック
#--------------------------------------------------------------------------
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

#--------------------------------------------------------------------------
#PowerShellバージョンチェック(3.0以上でなければ起動しない)
#--------------------------------------------------------------------------
$V_Check = (Get-Host).Version.Major
if($V_Check -ge 3){
    echo "PowerShellのバージョンが3.0以上です。"
}else{
    $result = $WS.Popup("PowerShellのバージョンが3.0未満のためScriptを終了します。")
    exit
}

#--------------------------------------------------------------------------
#監視対象（ホスト名orIP）の変数
#--------------------------------------------------------------------------
$Testhost = @()
$HostAliveCount =@()
$HostAliveFlag =@()

#Hosts.txtを$Hostsに格納
$Hosts = Get-Content ($scriptPath + "/Hosts.txt")
$Testhost = @()
#---自分用コメント----
#Get-Contentで複数行あると$Hostsは配列になるが、1行しかないと配列にならない。
#下のforeach処理で$Hostsを$Testhostに配列として代入する。

foreach ($HostArray in $Hosts) {
    #X各ホストの情報を格納する
    $Testhost += $HostArray
    #各ホスト死活監視用カウントに０を代入する
    $HostAliveCount += 0
    #各ホスト死活監視フラグにTrueを代入する
    $HostAliveFlag += $True
}

#--------------------------------------------------------------------------
#設定系の変数
#--------------------------------------------------------------------------
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
#メッセージ変数
#--------------------------------------------------------------------------
$Latest_stat　#最新ステータス
$MessageArray = @() #メッセージ表示用の配列
$echoAlive　#ステータス表示の死活表示
$pramhoshi #Ping失敗した時の星の数

for($j=0;$j -lt 20;$j++){
    $MessageArray += ""
}


$WS = New-Object -com Wscript.Shell

#--------------------------------------------------------------------------
#実行部分
#--------------------------------------------------------------------------
$result = $WS.Popup("Ping監視を開始します")
$now = Get-Date -Format G
$Latest_stat = ($now + " Ping Monitoring Start")
$MessageArray = LatestMessage $MessageArray $Latest_stat
PMessage $Testhost $HostAliveCount $HostAliveFlag $MessageArray $scriptPath
#--------------------------------------------------------------------------
#メインループ
#--------------------------------------------------------------------------
while(1){
    #logファイルが50kbyte以上になるとoldファイルを作る。
    if ((Get-ChildItem ($scriptpath + "\log.txt")).Length -ge 51200){
    Move-Item ($scriptpath + "\log.txt") log-old.txt -Force
    }

    for($j=0;$j -lt $Testhost.Count; $j++){
        #ping送付実施
        $pingAlive = @(Test-Connection $Testhost[$j] -Quiet -Count $PingCount)
            #ping応答がある場合
            if($pingAlive -eq $True){
                $HostAliveCount[$j] = 0
                if($HostAliveFlag[$j] -eq $True){
                    $now = Get-Date -Format G
                    $Latest_stat = ($now + " " + $Testhost[$j] + " is alive")
                    $MessageArray = LatestMessage $MessageArray $Latest_stat
                    PMessage $Testhost $HostAliveCount $HostAliveFlag $MessageArray $scriptPath
                #今まで死んでいたホストが立ち上がってきた場合
                }else{
                    $HostAliveFlag[$j] = $True
                    $now = Get-Date -Format G
                    $Latest_stat = ($now + " " + $Testhost[$j] + " is recovered")
                    $MessageArray = LatestMessage $MessageArray $Latest_stat
                    PMessage $Testhost $HostAliveCount $HostAliveFlag $MessageArray $scriptPath

                    #パトライト消灯
                    try{
                        $PateliteFlagClr = Invoke-WebRequest $PateliteCommandClr
                    }catch {
                        #失敗した場合、ステータスをclr_statに代入
                        $clr_stat = $_.Exception.status
                    }
                    $now = Get-Date -Format G
                    $Latest_stat = ($now + " patelite's nortification clearing...")
                    $MessageArray = LatestMessage $MessageArray $Latest_stat
                    PMessage $Testhost $HostAliveCount $HostAliveFlag $MessageArray $scriptPath

                    if ($clr_stat -eq "ConnectFailure" -eq $True){
                        #失敗
                        $Latest_stat = ($now + " patelite's nortification clear fault")
                        $MessageArray = LatestMessage $MessageArray $Latest_stat
                        PMessage $Testhost $HostAliveCount $HostAliveFlag $MessageArray $scriptPath

                    }else{
                        #成功
                        $Latest_stat = ($now + " patelite's nortification clear")
                        $MessageArray = LatestMessage $MessageArray $Latest_stat
                        PMessage $Testhost $HostAliveCount $HostAliveFlag $MessageArray $scriptPath
                    }
                    #test_statをクリアにする。
                    $clr_stat = ""
                }
            #ping応答がない場合
            }else{
                $HostAliveCount[$j] = $HostAliveCount[$j] + 1
                if($HostAliveFlag[$j] -eq $True){
                    $now = Get-Date -Format G
                    $Latest_stat = ($now + " " + $Testhost[$j] + " is not reachable")
                    $MessageArray = LatestMessage $MessageArray $Latest_stat
                    PMessage $Testhost $HostAliveCount $HostAliveFlag $MessageArray $scriptPath
                }else{
                    #何もしない。何かする場合はここに書く。
                }
            }
        #ping応答無し状態が$MaxAliveの回数を上回った場合、発報する
        if ($HostAliveCount[$j] -ge $MaxAlive){
            if($HostAliveFlag[$j] -eq $True){
                $HostAliveFlag[$j] = $False
                $now = Get-Date -Format G
                $Latest_stat = ($now + " " + $Testhost[$j] + " is dead")
                $MessageArray = LatestMessage $MessageArray $Latest_stat
                PMessage $Testhost $HostAliveCount $HostAliveFlag $MessageArray $scriptPath
                #パトライト発報
                $Latest_stat = ($now + " patelite's nortification starting...")
                $MessageArray = LatestMessage $MessageArray $Latest_stat
                PMessage $Testhost $HostAliveCount $HostAliveFlag $MessageArray $scriptPath
                try{
                    $PateliteFlag = Invoke-WebRequest $PateliteCommand
                }catch {
                    #失敗した場合、ステータスをlite_statに代入
                    $lite_stat = $_.Exception.status
                }
                $now = Get-Date -Format G
                if ($lite_stat -eq "ConnectFailure" -eq $True){
                    #失敗
                    $Latest_stat = ($now + " patelite's nortification fault")
                    $MessageArray = LatestMessage $MessageArray $Latest_stat
                    PMessage $Testhost $HostAliveCount $HostAliveFlag $MessageArray $scriptPath
                }else{
                    #成功
                    $Latest_stat = ($now + " patelite's nortification start")
                    $MessageArray = LatestMessage $MessageArray $Latest_stat
                    PMessage $Testhost $HostAliveCount $HostAliveFlag $MessageArray $scriptPath
                }
                #lite_statをクリアにする。
                $lite_stat = ""

            }else{
                #今は一度死ぬと何もしないが、定期的に何か実施する場合はここに入力。
                #何もしない
            }
        }
    }

#指定時間一時停止
Start-Sleep -s $SleepTime
}

