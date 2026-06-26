# Minimal mock of api.xiaoyuzhoufm.com content endpoints for simulator testing.
# Run:  pwsh -File scripts/mock-content.ps1   (listens on http://localhost:8099)
# Then: $env:XYZ_API_BASE = "http://localhost:8099"  before launching the app.
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:8099/")
$listener.Start()
Write-Host "mock-content on http://localhost:8099 (Ctrl+C to stop)"

$img = "https://picsum.photos/seed/xyz/120"
$inbox = @{ code=200; msg="OK"; data=@(
  @{ type="EPISODE"; eid="e1"; title="Summit: The Weekly Orbit 6.6";
     description="Hosts: Luma / Vega / Pico / Radish. Headlines: State of Play drops a wave of new titles.";
     duration=7800; pubDate="2026-06-13T09:00:00.000Z"; playCount=143; commentCount=1;
     image=@{ thumbnailUrl=$img; smallPicUrl=$img } },
  @{ type="EPISODE"; eid="e2"; title="183. Reading the Stars: Poems at the Edge of Night";
     description="Did the poets really turn away from the cold light of dusk? This episode makes the case.";
     duration=6900; pubDate="2026-06-12T18:00:00.000Z"; playCount=7941; commentCount=120;
     image=@{ thumbnailUrl=$img; smallPicUrl=$img } }
) } | ConvertTo-Json -Depth 8

$subs = @{ code=200; msg="OK"; data=@(
  @{ type="PODCAST"; pid="p1"; title="Cosmic Drift"; subscriptionOftenPlayed=$true;
     latestEpisodePubDate="2026-06-11T10:00:00.000Z"; image=@{ smallPicUrl=$img; thumbnailUrl=$img };
     podcasters=@(@{ nickname="Luma"; avatar=@{ picture=@{ smallPicUrl=$img; thumbnailUrl=$img } } },
                  @{ nickname="Vega"; avatar=@{ picture=@{ smallPicUrl=$img; thumbnailUrl=$img } } }) },
  @{ type="PODCAST"; pid="p2"; title="Code & Coffee";
     latestEpisodePubDate="2026-06-12T22:00:00.000Z"; image=@{ smallPicUrl=$img; thumbnailUrl=$img };
     podcasters=@(@{ nickname="Sol"; avatar=@{ picture=@{ smallPicUrl=$img; thumbnailUrl=$img } } }) }
) } | ConvertTo-Json -Depth 8

# episode/get returns the episode object under "data" (a map, not a list).
$episode = @{ code=200; msg="OK"; data=@{
  type="EPISODE"; eid="e2"; pid="p1";
  title="183. Reading the Stars: Poems at the Edge of Night";
  description="When we look up at the night sky, what are we really searching for? This episode drifts from the first telescope of childhood all the way to dark matter, the Fermi paradox, and that strange feeling of being small yet somehow healed.";
  duration=6900; pubDate="2026-06-12T18:00:00.000Z"; playCount=7941; commentCount=128;
  image=@{ thumbnailUrl=$img; smallPicUrl=$img; middlePicUrl=$img };
  podcast=@{ pid="p1"; title="Cosmic Drift"; image=@{ smallPicUrl=$img; thumbnailUrl=$img } };
  enclosure=@{ url="http://localhost:8099/audio/e2.wav" };
  media=@{ size=3236; mimeType="audio/wav"; source=@{ url="http://localhost:8099/audio/e2.wav"; mode="PUBLIC" } };
} } | ConvertTo-Json -Depth 8

# comment/list-primary returns the comment array under "data" + a totalCount.
$comments = @{ code=200; msg="OK"; totalCount=128; data=@(
  @{ id="c1"; type="COMMENT"; likeCount=328; ipLoc="Beijing";
     text="Halfway through I had to blink back tears - turns out I'm not the only one who stares at the night sky. Thank you.";
     author=@{ nickname="May"; avatar=@{ picture=@{ thumbnailUrl=$img; smallPicUrl=$img } } } },
  @{ id="c2"; type="COMMENT"; likeCount=156; ipLoc="Shanghai";
     text="So much packed in - already on my second listen. The Fermi paradox part blew my mind.";
     author=@{ nickname="Juan"; avatar=@{ picture=@{ thumbnailUrl=$img; smallPicUrl=$img } } } },
  @{ id="c3"; type="COMMENT"; likeCount=64; ipLoc="Chengdu";
     text="That closing line about feeling small yet healed will stay with me all week.";
     author=@{ nickname="Pico"; avatar=@{ picture=@{ thumbnailUrl=$img } } } }
) } | ConvertTo-Json -Depth 8

# Minimal 0.4s mono 8kHz 8-bit PCM WAV (~3.2KB) so the download+play loop is testable.
function New-SilenceWav {
  $sr=8000; $secs=0.4; $n=[int]($sr*$secs)
  $ms=New-Object System.IO.MemoryStream
  $bw=New-Object System.IO.BinaryWriter($ms)
  $bw.Write([Text.Encoding]::ASCII.GetBytes("RIFF")); $bw.Write([int](36+$n))
  $bw.Write([Text.Encoding]::ASCII.GetBytes("WAVE")); $bw.Write([Text.Encoding]::ASCII.GetBytes("fmt "))
  $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1)
  $bw.Write([int]$sr); $bw.Write([int]$sr); $bw.Write([int16]1); $bw.Write([int16]8)
  $bw.Write([Text.Encoding]::ASCII.GetBytes("data")); $bw.Write([int]$n)
  for ($i=0;$i -lt $n;$i++){ $bw.Write([byte]128) }   # 128 = silence for 8-bit PCM
  $bw.Flush(); return $ms.ToArray()
}
$wav = New-SilenceWav

# Refresh-flow test state: content endpoints answer 401 until the app has
# refreshed once via /app_auth_tokens.refresh, mimicking an expired access token.
$script:tokenRefreshed = $false

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $path = $ctx.Request.Url.AbsolutePath
  $method = $ctx.Request.HttpMethod

  # Token refresh: return new tokens in the BODY (matches the real upstream, which
  # the ultrazg/xyz proxy reads from the response body), and flip the gate open.
  if ($path -like "*app_auth_tokens.refresh*") {
    $refresh = @{ "x-jike-access-token"="NEW-ACCESS-TOKEN";
                  "x-jike-refresh-token"="NEW-REFRESH-TOKEN"; success=$true } | ConvertTo-Json
    $script:tokenRefreshed = $true
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($refresh)
    $ctx.Response.ContentType = "application/json; charset=utf-8"
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
    Write-Host "$method $path -> 200 (refresh)"
    continue
  }

  # Simulate an expired access token: every content endpoint 401s until refreshed.
  $isContent = ($path -like "*inbox*") -or ($path -like "*subscription*") -or
               ($path -like "*episode*") -or ($path -like "*comment*")
  if ($isContent -and -not $script:tokenRefreshed) {
    $ctx.Response.StatusCode = 401
    $err = @{ code=401; msg="UNAUTHORIZED" } | ConvertTo-Json
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($err)
    $ctx.Response.ContentType = "application/json; charset=utf-8"
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
    Write-Host "$method $path -> 401 (gated)"
    continue
  }

  if ($path -like "*/audio/*") {
    $ctx.Response.ContentType = "audio/wav"
    $ctx.Response.OutputStream.Write($wav, 0, $wav.Length)
    $ctx.Response.Close()
    continue
  }
  $body = if ($path -like "*subscription*") { $subs }
          elseif ($path -like "*episode*") { $episode }
          elseif ($path -like "*comment*") { $comments }
          else { $inbox }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
  $ctx.Response.ContentType = "application/json; charset=utf-8"
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.Close()
  Write-Host "$method $path -> 200"
}
