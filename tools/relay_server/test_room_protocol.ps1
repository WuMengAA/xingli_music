# cl15 radio room protocol test: create public/private, join, password, public list.
$ErrorActionPreference = 'Stop'
$uri = 'ws://127.0.0.1:8092/ws'

function Connect-Ws {
    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $ws.ConnectAsync($uri, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
    return $ws
}

function Send-Json($ws, $obj) {
    $json = $obj | ConvertTo-Json -Compress -Depth 10
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $seg = [System.ArraySegment[byte]]::new($bytes)
    $base = [System.Net.WebSockets.WebSocket]$ws
    $task = $base.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None)
    $task.GetAwaiter().GetResult()
}

function Receive-Json($ws) {
    $buf = [System.ArraySegment[byte]]::new([byte[]]::new(8192))
    $ms = [System.IO.MemoryStream]::new()
    do {
        $base = [System.Net.WebSockets.WebSocket]$ws
        $task = $base.ReceiveAsync($buf, [System.Threading.CancellationToken]::None)
        $res = $task.GetAwaiter().GetResult()
        $ms.Write($buf.Array, 0, $res.Count)
    } while (-not $res.EndOfMessage)
    $txt = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
    return ($txt | ConvertFrom-Json)
}

$script:fail = 0
function Assert-True($cond, $msg) {
    if ($cond) { Write-Host "  [PASS] $msg" -ForegroundColor Green }
    else { Write-Host "  [FAIL] $msg" -ForegroundColor Red; $script:fail++ }
}

# 1. create public campus room
Write-Host "1) create public campus room ABC123"
$h1 = Connect-Ws
Send-Json $h1 @{ ctl='join'; room='ABC123'; name='HostA'; host=$true; public=$true; mode='campus'; capacity=100 }
$r1 = Receive-Json $h1
Assert-True ($r1.ctl -eq 'ready' -and $r1.id) "public create -> ready(id=$($r1.id))"
Assert-True ($r1.meta.mode -eq 'campus' -and $r1.meta.capacity -eq 100 -and $r1.meta.public) "meta ok(mode=campus,cap=100,public)"

# 2. join public room (no password)
Write-Host "2) join public room ABC123"
$c1 = Connect-Ws
Send-Json $c1 @{ ctl='join'; room='ABC123'; name='ClientB'; host=$false }
$r2 = Receive-Json $c1
Assert-True ($r2.ctl -eq 'ready') "public join -> ready"
$j1 = Receive-Json $h1
Assert-True ($j1.ctl -eq 'peerJoin') "host receives peerJoin"

# 3. public room list contains it
Write-Host "3) GET /api/rooms"
$rooms = Invoke-RestMethod -Uri http://127.0.0.1:8092/api/rooms
Assert-True ($rooms.rooms.Count -ge 1) "public list >= 1 room"
$abc = $rooms.rooms | Where-Object { $_.code -eq 'ABC123' }
Assert-True ($abc -and $abc.members -eq 2 -and $abc.public) "list has ABC123(members=2)"

# 4. create private room with password
Write-Host "4) create private room XYZ999 (pw ab12)"
$h2 = Connect-Ws
Send-Json $h2 @{ ctl='join'; room='XYZ999'; name='HostC'; host=$true; public=$false; mode='listen'; capacity=5; password='ab12' }
$r4 = Receive-Json $h2
Assert-True ($r4.ctl -eq 'ready') "private create -> ready"
Assert-True ($r4.meta.capacity -eq 5 -and -not $r4.meta.public) "meta ok(listen,cap=5,private)"

# 5. wrong password -> error
Write-Host "5) wrong password join"
$c2 = Connect-Ws
Send-Json $c2 @{ ctl='join'; room='XYZ999'; name='Someone'; host=$false; password='wrong' }
$r5 = Receive-Json $c2
Assert-True ($r5.ctl -eq 'error' -and $r5.msg -eq 'wrong password') "wrong pw -> error(wrong password)"

# 6. correct password -> ready
Write-Host "6) correct password join"
$c3 = Connect-Ws
Send-Json $c3 @{ ctl='join'; room='XYZ999'; name='Someone'; host=$false; password='ab12' }
$r6 = Receive-Json $c3
Assert-True ($r6.ctl -eq 'ready') "correct pw -> ready"

# 7. private room not in public list
Write-Host "7) private room hidden from public list"
$rooms2 = Invoke-RestMethod -Uri http://127.0.0.1:8092/api/rooms
$priv = $rooms2.rooms | Where-Object { $_.code -eq 'XYZ999' }
Assert-True (-not $priv) "private room not in public list"

# 8. duplicate host same room -> room exists
Write-Host "8) duplicate host room ABC123"
$h3 = Connect-Ws
Send-Json $h3 @{ ctl='join'; room='ABC123'; name='Snatcher'; host=$true; public=$true; mode='campus'; capacity=100 }
$r8 = Receive-Json $h3
Assert-True ($r8.ctl -eq 'error' -and $r8.msg -eq 'room exists') "duplicate -> error(room exists)"

# 9. join nonexistent room -> room not found
Write-Host "9) join nonexistent room"
$c4 = Connect-Ws
Send-Json $c4 @{ ctl='join'; room='NOPE00'; name='Nobody'; host=$false }
$r9 = Receive-Json $c4
Assert-True ($r9.ctl -eq 'error' -and $r9.msg -eq 'room not found') "nonexistent -> error(room not found)"

# cleanup
foreach ($w in @($h1,$c1,$h2,$c2,$c3,$h3,$c4)) {
    try { $w.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', [System.Threading.CancellationToken]::None).GetAwaiter().GetResult() } catch {}
}

Write-Host ""
if ($script:fail -gt 0) { Write-Host "RESULT: $script:fail failed" -ForegroundColor Red; exit 1 }
else { Write-Host "RESULT: all passed" -ForegroundColor Green; exit 0 }
