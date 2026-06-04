# lib/wer.ps1 — Word Error Rate computation
# WER = (substitutions + insertions + deletions) / reference-word-count
# Normalization: lowercase, strip punctuation, collapse whitespace.
# Normalization is documented here because WER numbers must be reproducible.

function Normalize-Text {
    param([string]$text)
    if ([string]::IsNullOrEmpty($text)) { return "" }
    # lowercase
    $t = $text.ToLower()
    # expand common contractions to avoid splitting them into fragments
    $t = $t -replace "won't", "will not"
    $t = $t -replace "can't", "cannot"
    $t = $t -replace "n't", " not"
    $t = $t -replace "'re", " are"
    $t = $t -replace "'ve", " have"
    $t = $t -replace "'ll", " will"
    $t = $t -replace "'d", " would"
    $t = $t -replace "'m", " am"
    # strip all remaining punctuation
    $t = $t -replace "[^\w\s]", " "
    # collapse whitespace
    $t = ($t -split "\s+" | Where-Object { $_ -ne "" }) -join " "
    return $t.Trim()
}

function Compute-WER {
    param([string]$Reference, [string]$Hypothesis)
    $ref = Normalize-Text $Reference
    $hyp = Normalize-Text $Hypothesis

    $refWords = if ($ref -eq "") { @() } else { $ref -split "\s+" }
    $hypWords = if ($hyp -eq "") { @() } else { $hyp -split "\s+" }

    if ($refWords.Count -eq 0) {
        # empty reference: WER = 1 if hypothesis has words, 0 if also empty
        return if ($hypWords.Count -eq 0) { [double]0.0 } else { [double]1.0 }
    }

    $dist = Compute-EditDistance $refWords $hypWords
    return [Math]::Round([double]$dist / [double]$refWords.Count, 4)
}

function Compute-EditDistance {
    param([string[]]$A, [string[]]$B)
    $m = $A.Count
    $n = $B.Count

    # standard Levenshtein over word sequences
    # Use a flat int[] of size (m+1)*(n+1); index as dp[i*(n+1)+j]
    $dp = New-Object int[] (($m + 1) * ($n + 1))

    for ($i = 0; $i -le $m; $i++) { $dp[$i * ($n + 1) + 0] = $i }
    for ($j = 0; $j -le $n; $j++) { $dp[0 * ($n + 1) + $j] = $j }

    for ($i = 1; $i -le $m; $i++) {
        for ($j = 1; $j -le $n; $j++) {
            if ($A[$i - 1] -eq $B[$j - 1]) {
                $dp[$i * ($n+1) + $j] = $dp[($i-1) * ($n+1) + ($j-1)]
            } else {
                $ins = $dp[ $i    * ($n+1) + ($j-1)] + 1
                $del = $dp[($i-1) * ($n+1) +  $j   ] + 1
                $sub = $dp[($i-1) * ($n+1) + ($j-1)] + 1
                $dp[$i * ($n+1) + $j] = [Math]::Min($ins, [Math]::Min($del, $sub))
            }
        }
    }
    return $dp[$m * ($n + 1) + $n]
}

# Self-test: "the cat sat" vs "the cat sit" → WER = 1/3 ≈ 0.3333
function Test-WER {
    $wer = Compute-WER "the cat sat" "the cat sit"
    $expected = [Math]::Round(1.0 / 3.0, 4)
    if ([Math]::Abs($wer - $expected) -lt 0.001) {
        Write-Host "  PASS  WER self-test: ref='the cat sat' hyp='the cat sit' → $wer" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  FAIL  WER self-test: expected $expected got $wer" -ForegroundColor Red
        return $false
    }
}
