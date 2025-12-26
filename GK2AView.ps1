# =========================================================
# GK2AVIEW - SATELLITE IR PROCESSING
# MODE  : FULL AUTO
# STYLE : CLEAN CODE + HACKER SLANK (ASCII SAFE)
#
# STEP 1  : enhance-ir.py        -> OUTPUT\2.IR
# STEP 2  : Sanchez IR false     -> OUTPUT\3.IR_COLOR
# STEP 3  : Sanchez NORMAL       -> OUTPUT\1.NORMAL
# STEP 4  : Generate MP4 (3x)    -> *_MP4
# =========================================================

# ---------------- HELPER FUNCTIONS ----------------
function Banner($text, $color = "Cyan") {
    Write-Host ""
    Write-Host "[>>] $text" -ForegroundColor $color
}

function Clean-Dir($dir) {
    Write-Host "    [+] wipe folder -> $dir" -ForegroundColor DarkYellow
    Get-ChildItem "$dir\*" -Recurse -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------- BASE PATH (PORTABLE MODE) ----------------
$BASE_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition

# -------------------------------------------------
# PIPELINE TIMER INIT
# -------------------------------------------------
$PIPE_START = Get-Date
$SW_PIPE = [System.Diagnostics.Stopwatch]::StartNew()


# ---------------- BOOT ----------------
Banner "GK2AVIEW START - SYSTEM ONLINE" Green

# ---------------- PATH SETUP (RELATIVE) ----------------
$INPUT_DIR   = Join-Path $BASE_DIR "INPUT"
$OUTPUT_BASE = Join-Path $BASE_DIR "OUTPUT"

# IMAGE OUTPUT (URUTAN BENAR)
$OUTPUT_NORMAL    = Join-Path $OUTPUT_BASE "1.NORMAL"
$OUTPUT_IR        = Join-Path $OUTPUT_BASE "2.IR"
$OUTPUT_IR_COLOR  = Join-Path $OUTPUT_BASE "3.IR_COLOR"

# MP4 OUTPUT (URUTAN FINAL & TIDAK BOLEH BERUBAH)
$NORMAL_MP4_DIR   = Join-Path $OUTPUT_BASE "4.NORMAL_MP4"
$IR_MP4_DIR       = Join-Path $OUTPUT_BASE "5.IR_MP4"
$IR_COLOR_MP4_DIR = Join-Path $OUTPUT_BASE "6.IR_COLOR_MP4"

# TOOLS
$PROGRAM_DIR = Join-Path $BASE_DIR "PROGRAM"

$PY_SOURCE  = Join-Path $PROGRAM_DIR "Enhance-IR\enhance-ir.py"
$PY_TARGET  = Join-Path $INPUT_DIR   "enhance-ir.py"

$SANCHEZ = Join-Path $PROGRAM_DIR "Sanchez\Sanchez.exe"
$FFMPEG  = Join-Path $PROGRAM_DIR `
    "ffmpeg\bin\ffmpeg.exe"

$GRADIENT_IR  = Join-Path $PROGRAM_DIR "Sanchez\Resources\Gradients\DarkRed-Blue.json"
$UNDERLAY_MAP = Join-Path $PROGRAM_DIR "Sanchez\Resources\world.200412.3x21600x10800.jpg"

# ---------------- VALIDATION ----------------
Banner "Checking environment..."

foreach ($p in @(
    $INPUT_DIR, $PY_SOURCE, $SANCHEZ, $FFMPEG,
    $GRADIENT_IR, $UNDERLAY_MAP
)) {
    if (!(Test-Path $p)) {
        Write-Host "[!!] MISSING: $p" -ForegroundColor Red
        exit
    }
}

# ---------------- ENSURE OUTPUT DIRS ----------------
New-Item -ItemType Directory -Force -Path `
  $OUTPUT_NORMAL,
  $OUTPUT_IR,
  $OUTPUT_IR_COLOR,
  $NORMAL_MP4_DIR,
  $IR_MP4_DIR,
  $IR_COLOR_MP4_DIR | Out-Null

# ---------------- CLEAN OUTPUT ----------------
Banner "Cleaning output folders (fresh run)"

foreach ($d in @(
    $OUTPUT_NORMAL,
    $OUTPUT_IR,
    $OUTPUT_IR_COLOR,
    $NORMAL_MP4_DIR,
    $IR_MP4_DIR,
    $IR_COLOR_MP4_DIR
)) {
    Clean-Dir $d
}

# =========================================================
# STEP 1 - PYTHON IR ENHANCE
# =========================================================
Banner "STEP 1 - Python IR enhance" Yellow

Copy-Item $PY_SOURCE $PY_TARGET -Force

Push-Location $INPUT_DIR
python3 enhance-ir.py -s -o "$INPUT_DIR"
$pyExit = $LASTEXITCODE
Pop-Location

Remove-Item $PY_TARGET -Force -ErrorAction SilentlyContinue

if ($pyExit -ne 0) {
    Write-Host "[!!] enhance-ir.py FAILED" -ForegroundColor Red
    exit
}

Move-Item "$INPUT_DIR\*_ENHANCED.jpg" $OUTPUT_IR -Force
Write-Host "    [+] IR enhanced OK" -ForegroundColor Green

# =========================================================
# STEP 2 - SANCHEZ IR FALSE COLOR
# =========================================================
Banner "STEP 2 - Sanchez IR false color" Yellow

& $SANCHEZ `
  -s "$INPUT_DIR" `
  -o "$OUTPUT_IR_COLOR" `
  -F JPG `
  -r 4 `
  -g "$GRADIENT_IR" `
  -c "0,8-1,0" `
  -u "$UNDERLAY_MAP" `
  -f `
  -v

# =========================================================
# STEP 3 - SANCHEZ NORMAL
# =========================================================
Banner "STEP 3 - Sanchez NORMAL cloud" Yellow

& $SANCHEZ `
  -s "$INPUT_DIR" `
  -o "$OUTPUT_NORMAL" `
  -F JPG `
  -r 4 `
  -u "$UNDERLAY_MAP" `
  -f `
  -v
  
$COUNT_NORMAL   = (Get-ChildItem "$OUTPUT_NORMAL\*.jpg" -ErrorAction SilentlyContinue).Count
$COUNT_IR       = (Get-ChildItem "$OUTPUT_IR\*.jpg" -ErrorAction SilentlyContinue).Count
$COUNT_IR_COLOR = (Get-ChildItem "$OUTPUT_IR_COLOR\*.jpg" -ErrorAction SilentlyContinue).Count


# =========================================================
# STEP 3.5 - TIMESTAMP OVERLAY (UTC ONLY + SMALL LOGO)
# =========================================================
Banner "STEP 3.5 - Timestamp overlay (UTC only + small logo)" Yellow

$MAGICK = Join-Path $PROGRAM_DIR "ImageMagick\magick.exe"
$FONT   = "C:/Windows/Fonts/arial.ttf"

# === LOGO FILE ===
$LOGO = "E:\GK2AView\PROGRAM\LOGO\LOGO.png"

# ---------- CONFIG ----------
$SAT_NAME = "GK-2A"
$MODE     = "LRIT"

function Apply-Timestamp($dir, $ext, $label) {

    Write-Host "    [+] stamping $label ($ext, UTC)" -ForegroundColor Cyan

    Get-ChildItem "$dir\*.$ext" | ForEach-Object {

        if ($_.Name -match '_(\d{8})_(\d{6})') {

            # === HARD UTC LOCK ===
            $dtUTC = [DateTime]::SpecifyKind(
                [datetime]::ParseExact(
                    "$($matches[1])$($matches[2])",
                    "yyyyMMddHHmmss",
                    $null
                ),
                [DateTimeKind]::Utc
            )

            $TEXT = @"
$SAT_NAME | $MODE | $label
$($dtUTC.ToString("yyyy-MM-dd HH:mm:ss 'UTC'"))
"@

            & $MAGICK `
              "$($_.FullName)" `
              "(" "$LOGO" -resize 360x360 ")" `
              -gravity NorthEast `
              -geometry +20+20 `
              -composite `
              -gravity NorthWest `
              -font "$FONT" `
              -pointsize 50 `
              -fill white `
              -undercolor "rgba(0,0,0,0.80)" `
              -annotate +20+20 "$TEXT" `
              "$($_.FullName)"
        }
    }
}

# =========================================================
# APPLY
# =========================================================
Apply-Timestamp $OUTPUT_NORMAL   "jpg" "NORMAL"
Apply-Timestamp $OUTPUT_IR       "jpg" "IR"
Apply-Timestamp $OUTPUT_IR_COLOR "jpg" "IR_COLOR"

Write-Host "    [+] Timestamp + logo overlay DONE (CLEAN)" -ForegroundColor Green

# =========================================================
# STEP 4 - MP4 GENERATION (TIME LOCKED + SMOOTH - FINAL)
# =========================================================
Banner "STEP 4 - MP4 render (time locked + smooth)" Yellow

$ts = Get-Date -Format "yyyyMMdd_HHmm"

function Make-MP4($srcDir, $ext, $outDir, $label) {

    Write-Host "    -> MP4 $label => $outDir (time ordered)" -ForegroundColor Cyan

    $list = Join-Path $srcDir "_list.txt"

    # === SORT BY TIMESTAMP IN FILENAME (YYYYMMDD_HHMMSS) ===
    Get-ChildItem "$srcDir\*.$ext" |
        Sort-Object {
            if ($_.Name -match '_(\d{8})_(\d{6})') {
                "$($matches[1])$($matches[2])"
            } else {
                $_.Name
            }
        } |
        ForEach-Object { "file '$($_.FullName)'" } |
        Set-Content $list -Encoding ASCII

    & $FFMPEG `
        -y `
        -loglevel error `
        -fflags +genpts `
        -f concat `
        -safe 0 `
        -vsync vfr `
        -i "$list" `
        -vf "minterpolate=fps=10:mi_mode=blend,scale=trunc(iw/2)*2:trunc(ih/2)*2" `
        -c:v libx264 `
        -preset slower `
        -crf 16 `
        -pix_fmt yuv420p `
        -movflags +faststart `
        (Join-Path $outDir "$label`_$ts.mp4")

    if (!(Test-Path (Join-Path $outDir "$label`_$ts.mp4"))) {
        Write-Host "    [!!] MP4 FAILED: $label" -ForegroundColor Red
    }

    Remove-Item $list -Force -ErrorAction SilentlyContinue
}

# -------------------------------------------------
# EXECUTION ORDER (FIXED)
# -------------------------------------------------
Make-MP4 $OUTPUT_NORMAL   "jpg" $NORMAL_MP4_DIR   "GK2A_NORMAL"   "NORMAL"
Make-MP4 $OUTPUT_IR       "jpg" $IR_MP4_DIR       "GK2A_IR"       "IR"
Make-MP4 $OUTPUT_IR_COLOR "jpg" $IR_COLOR_MP4_DIR "GK2A_IR_COLOR" "IR COLOR"

$MP4_COUNT =
    (Get-ChildItem "$NORMAL_MP4_DIR\*.mp4" -ErrorAction SilentlyContinue).Count +
    (Get-ChildItem "$IR_MP4_DIR\*.mp4" -ErrorAction SilentlyContinue).Count +
    (Get-ChildItem "$IR_COLOR_MP4_DIR\*.mp4" -ErrorAction SilentlyContinue).Count


# -------------------------------------------------
# ---------------- PIPELINE SUMMARY ----------------
# -------------------------------------------------
$SW_PIPE.Stop()
$PIPE_END = Get-Date
$ELAPSED  = $SW_PIPE.Elapsed

Write-Host ""
Write-Host "================ PIPELINE STATS ================" -ForegroundColor DarkCyan
Write-Host " Satellite     : GK-2A"                         -ForegroundColor Gray
Write-Host " Mode          : LRIT"                          -ForegroundColor Gray
Write-Host " Start Time    : $PIPE_START"                  -ForegroundColor Gray
Write-Host " End Time      : $PIPE_END"                    -ForegroundColor Gray
Write-Host " Runtime       : $($ELAPSED.ToString())"       -ForegroundColor Yellow
Write-Host "------------------------------------------------" -ForegroundColor DarkGray
Write-Host " NORMAL Images : $COUNT_NORMAL"                -ForegroundColor Cyan
Write-Host " IR Images     : $COUNT_IR"                    -ForegroundColor Cyan
Write-Host " IR COLOR Img  : $COUNT_IR_COLOR"              -ForegroundColor Cyan
Write-Host " MP4 Output    : $MP4_COUNT file(s)"           -ForegroundColor Green
Write-Host "================================================" -ForegroundColor DarkCyan

Banner "PIPELINE DONE - DATA CLEAN - VIDEO READY" Green




