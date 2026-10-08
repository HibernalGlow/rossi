# Whole-book translation: one server for all pages, per-page loop, resumable.
# ASCII-ONLY ON PURPOSE: PS 5.1 reads .ps1 as ANSI, so a stray CJK char aborts the whole script.
# Usage: scp this to the Windows box, then (from a HELD-OPEN ssh session)
#        powershell -NoProfile -ExecutionPolicy Bypass -File D:\book_runner.ps1
$ErrorActionPreference='Continue'

# Session 0 (ssh) cannot read the Windows credential manager (ERROR_NO_SUCH_LOGON_SESSION),
# so the secret must come from the environment. Any non-empty value works for a local endpoint.
$env:KOHARU_SECRET_OPENAI_COMPATIBLE='local'

$srv   = 'D:\llama\llama-server.exe'
$bin   = 'D:\koharu-run\run.exe'
$model = 'D:\murasaki.gguf'
$alias = 'murasaki'
$src   = 'D:\book\src'
$out   = 'D:\book\out_murasaki'

# Optional: the no-annotation instruction. It is Chinese text, so it lives in a UTF-8 file
# (exact sentence in SKILL.md) instead of inline in this ASCII-only script.
$instr = (Get-Content 'D:\book\instr.txt' -Raw -Encoding UTF8).Trim()

New-Item -ItemType Directory -Force -Path $out | Out-Null
Get-Process run -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# -ngl 99 offloads every layer to the GPU (the CUDA part; CPU generation is ~5 tok/s vs ~70).
$p = Start-Process -FilePath $srv -ArgumentList '-m',$model,'-ngl','99','-c','8192','--host','127.0.0.1','--port','8080','--alias',$alias -NoNewWindow -PassThru -RedirectStandardOutput 'D:\srv.out' -RedirectStandardError 'D:\srv.err'
$ok=$false
for ($i=0; $i -lt 120; $i++) { Start-Sleep -Seconds 2; try { $q=Invoke-WebRequest -Uri 'http://127.0.0.1:8080/health' -TimeoutSec 3 -UseBasicParsing; if ($q.StatusCode -eq 200) { $ok=$true; break } } catch {} }
Write-Host ("SERVER_READY=" + $ok)
if (-not $ok) { exit 1 }

$files = Get-ChildItem -Recurse -File -Path $src | Where-Object { $_.Extension -in '.webp','.jpg','.png' } | Sort-Object FullName
$n = 0
$total = $files.Count
foreach ($f in $files) {
  $n++
  $dest = Join-Path $out ($f.BaseName + '.png')
  if (Test-Path $dest) { Write-Host ("[{0}/{1}] SKIP {2}" -f $n,$total,$f.Name); continue }
  $t0 = Get-Date
  # json-schema: llama.cpp compiles the JSON Schema into a GBNF grammar. With json-object the
  # model invents its own key names (e.g. "translation" instead of "text") and parsing fails.
  & $bin -i $f.FullName -o $dest --target-language zh-Hans --translation-instructions $instr --provider openai-compatible --base-url http://127.0.0.1:8080/v1 --llm $alias --response-format json-schema *> 'D:\book\last_page.log'
  $rc = $LASTEXITCODE
  $secs = [int]((Get-Date) - $t0).TotalSeconds
  $tr = (Select-String -Path 'D:\book\last_page.log' -Pattern 'translation finished in [0-9.]+s' | Select-Object -Last 1).Matches.Value
  # rc != 0 is common (teardown crash 0xC0000005) while the png was written fine;
  # judge by "file exists + dimensions match", not by rc.
  Write-Host ("[{0}/{1}] {2} rc={3} {4}s {5}" -f $n,$total,$f.Name,$rc,$secs,$tr)
}

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Write-Host 'BOOK DONE'
