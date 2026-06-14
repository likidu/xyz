# Minimal mock of api.xiaoyuzhoufm.com content endpoints for simulator testing.
# Run:  pwsh -File scripts/mock-content.ps1   (listens on http://localhost:8099)
# Then: $env:XYZ_API_BASE = "http://localhost:8099"  before launching the app.
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:8099/")
$listener.Start()
Write-Host "mock-content on http://localhost:8099 (Ctrl+C to stop)"

$img = "https://picsum.photos/seed/xyz/120"
$inbox = @{ code=200; msg="OK"; data=@{ data=@(
  @{ type="EPISODE"; eid="e1"; title="Summit: The Weekly Orbit 6.6";
     description="Hosts: Luma / Vega / Pico / Radish. Headlines: State of Play drops a wave of new titles.";
     duration=7800; pubDate="2026-06-13T09:00:00.000Z"; playCount=143; commentCount=1;
     image=@{ thumbnailUrl=$img; smallPicUrl=$img } },
  @{ type="EPISODE"; eid="e2"; title="183. Reading the Stars: Poems at the Edge of Night";
     description="Did the poets really turn away from the cold light of dusk? This episode makes the case.";
     duration=6900; pubDate="2026-06-12T18:00:00.000Z"; playCount=7941; commentCount=120;
     image=@{ thumbnailUrl=$img; smallPicUrl=$img } }
) } } | ConvertTo-Json -Depth 8

$subs = @{ code=200; msg="OK"; data=@{ data=@(
  @{ type="PODCAST"; pid="p1"; title="Cosmic Drift"; subscriptionOftenPlayed=$true;
     latestEpisodePubDate="2026-06-11T10:00:00.000Z"; image=@{ smallPicUrl=$img; thumbnailUrl=$img };
     podcasters=@(@{ nickname="Luma"; avatar=@{ picture=@{ smallPicUrl=$img; thumbnailUrl=$img } } },
                  @{ nickname="Vega"; avatar=@{ picture=@{ smallPicUrl=$img; thumbnailUrl=$img } } }) },
  @{ type="PODCAST"; pid="p2"; title="Code & Coffee";
     latestEpisodePubDate="2026-06-12T22:00:00.000Z"; image=@{ smallPicUrl=$img; thumbnailUrl=$img };
     podcasters=@(@{ nickname="Sol"; avatar=@{ picture=@{ smallPicUrl=$img; thumbnailUrl=$img } } }) }
) } } | ConvertTo-Json -Depth 8

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $path = $ctx.Request.Url.AbsolutePath
  $body = if ($path -like "*subscription*") { $subs } else { $inbox }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
  $ctx.Response.ContentType = "application/json; charset=utf-8"
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.Close()
}
