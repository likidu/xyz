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

# discovery-feed/list is double-nested (data.data[]) and selected by loadMoreKey.
function New-DiscEpisode($eid, $title, $show, $dur, $when, $comments) {
  @{ episode = @{ type="EPISODE"; eid=$eid; title=$title; duration=$dur;
       pubDate=$when; commentCount=$comments;
       image=@{ thumbnailUrl=$img; smallPicUrl=$img };
       podcast=@{ title=$show; image=@{ smallPicUrl=$img; thumbnailUrl=$img } } };
     recommendation="" }
}
function New-DiscModule($title, $desc, $items) {
  @{ title=$title; moduleType="X"; targetType="EPISODE"; description=$desc; target=$items }
}
function New-DiscPayload($modules) {
  # Real upstream shape: feed entries live directly under top-level "data" (single-nested),
  # like inbox/subscription. The proxy DOC double-wraps (data.data) because ReturnJson nests
  # the whole upstream body under another "data" — that wrapper is a proxy artifact.
  @{ code=200; msg="OK"; loadMoreKey="pick"; data=@(
       @{ type="DISCOVERY_COLLECTION"; data=$modules }
     ) } | ConvertTo-Json -Depth 12
}

$discDefault = New-DiscPayload @(
  (New-DiscModule "大家都在听" "" @(
     (New-DiscEpisode "d1" "Why we drift toward the cosmos" "Cosmic Drift" 3480 "2026-06-23T09:00:00.000Z" 1200),
     (New-DiscEpisode "d2" "Three years remote, five lessons" "Code & Coffee" 2520 "2026-06-24T09:00:00.000Z" 863))),
  (New-DiscModule "编辑精选" "Hand-picked by our editors" @(
     (New-DiscEpisode "d3" "Songs that quietly healed you" "Late Night Radio" 3960 "2026-06-21T09:00:00.000Z" 2400)))
)
$discTopic = New-DiscPayload @(
  (New-DiscModule "中年人运动全面指南" "How do we approach movement in our prime years?" @(
     (New-DiscEpisode "d4" "After 100km across one city" "City Walks" 2220 "2026-06-20T09:00:00.000Z" 517),
     (New-DiscEpisode "d5" "If a black hole could speak" "Interstellar Nights" 2940 "2026-06-18T09:00:00.000Z" 1000)))
)
$discHot = New-DiscPayload @(
  (New-DiscModule "最热榜" "" @(
     (New-DiscEpisode "d6" "The science of flavor in a pour-over" "Useless Beauty" 1980 "2026-06-17T09:00:00.000Z" 402)))
)

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

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $path = $ctx.Request.Url.AbsolutePath
  if ($path -like "*/audio/*") {
    $ctx.Response.ContentType = "audio/wav"
    $ctx.Response.OutputStream.Write($wav, 0, $wav.Length)
    $ctx.Response.Close()
    continue
  }
  $body = if ($path -like "*discovery-feed*") {
            $reader = New-Object System.IO.StreamReader($ctx.Request.InputStream)
            $raw = $reader.ReadToEnd(); $reader.Close()
            if ($raw -like "*discoveryTopic*") { $discTopic }
            elseif ($raw -like "*mediumDiscoveryPictorial*") { $discHot }
            else { $discDefault }
          }
          elseif ($path -like "*subscription*") { $subs }
          elseif ($path -like "*episode*") { $episode }
          elseif ($path -like "*comment*") { $comments }
          else { $inbox }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
  $ctx.Response.ContentType = "application/json; charset=utf-8"
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.Close()
}
