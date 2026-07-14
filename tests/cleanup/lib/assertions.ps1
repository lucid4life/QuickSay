# lib/assertions.ps1 — assertion engine for the cleanup regression harness.
# Mirrors the tokenizer used in the Phase-1 history miner
# (tests/transcription/tools/mine-history.mjs) so classifications line up.

$script:Contractions = @{
    "don't"="do not"; "doesn't"="does not"; "didn't"="did not"; "can't"="can not";
    "cannot"="can not"; "won't"="will not"; "wouldn't"="would not"; "couldn't"="could not";
    "shouldn't"="should not"; "isn't"="is not"; "aren't"="are not"; "wasn't"="was not";
    "weren't"="were not"; "hasn't"="has not"; "haven't"="have not"; "hadn't"="had not";
    "i'm"="i am"; "i've"="i have"; "i'll"="i will"; "i'd"="i would";
    "you're"="you are"; "you've"="you have"; "you'll"="you will"; "you'd"="you would";
    "we're"="we are"; "we've"="we have"; "we'll"="we will"; "we'd"="we would";
    "they're"="they are"; "they've"="they have"; "they'll"="they will";
    "it's"="it is"; "that's"="that is"; "there's"="there is"; "what's"="what is";
    "let's"="let us"; "he's"="he is"; "she's"="she is"; "who's"="who is";
    "gonna"="going to"; "wanna"="want to"; "gotta"="got to"; "kinda"="kind of";
    "sorta"="sort of"
}
$script:NumberWords = @{
    "zero"="0"; "one"="1"; "two"="2"; "three"="3"; "four"="4"; "five"="5"; "six"="6";
    "seven"="7"; "eight"="8"; "nine"="9"; "ten"="10"; "eleven"="11"; "twelve"="12";
    "thirteen"="13"; "fourteen"="14"; "fifteen"="15"; "sixteen"="16"; "seventeen"="17";
    "eighteen"="18"; "nineteen"="19"; "twenty"="20"; "thirty"="30"; "forty"="40";
    "fifty"="50"; "sixty"="60"; "seventy"="70"; "eighty"="80"; "ninety"="90";
    "hundred"="100"; "thousand"="1000"; "third"="3"; "first"="1"; "second"="2"
}
# Tokens the cleaner may remove freely (fillers) …
$script:Fillers = @("um","uh","uhm","er","ah","hmm","mhm","like","basically","so","well",
    "okay","ok","right","actually","yeah","alright","just","literally","and","you","know",
    "i","mean","kind","sort","of","hey")
# … and tokens it may ADD freely (grammar glue). Deliberately excludes pronouns
# (perspective swaps are harm) and "not" (negation injection is harm).
$script:GlueWords = @("the","a","an","is","are","was","were","to","of","and","or","in","on",
    "at","for","with","as","that","this","be","been","do","does","has","have","had","will",
    "am","it","its","if","then","than","so","but","by","from","when","after","before","please",
    "because","into","them","these","those")
$script:EmailScaffold = @("hi","hello","dear","best","regards","sincerely","thanks","thank",
    "you","cheers","team","kind","warm","chance","over","send","get","a","when")
$script:Hedges = @("maybe","probably","perhaps","might","possibly","hopefully")
$script:HedgePhrases = @("i think","i guess","i believe","i feel like","pretty sure","kind of","sort of","i suppose")

function Get-CleanupTokens([string]$text) {
    $t = " " + $text.ToLowerInvariant() + " "
    foreach ($k in $script:Contractions.Keys) { $t = $t.Replace($k, $script:Contractions[$k]) }
    # decimal fractions: "one and a half" -> "1.5"-style tokens on both sides
    $t = $t -replace "\b(\w+) and a half\b", '$1.5'
    # keep decimal points inside numbers ("1.5" stays one token)
    $t = $t -replace "(?<![0-9])\.|\.(?![0-9])", " "
    $t = $t -replace "[^a-z0-9.' ]+", " "
    $toks = @()
    foreach ($w in ($t -split "\s+")) {
        if ($w -eq "") { continue }
        $w = ($w -replace "'", "").Trim(".")
        if ($w -eq "") { continue }
        if ($script:NumberWords.ContainsKey($w)) { $w = $script:NumberWords[$w] }
        if ($w -match "^(\w+)\.5$" -and $script:NumberWords.ContainsKey($Matches[1])) {
            $w = $script:NumberWords[$Matches[1]] + ".5"
        }
        $toks += $w
    }
    return $toks
}

function Get-TokenCounts([array]$toks) {
    $m = @{}
    foreach ($t in $toks) { $m[$t] = 1 + $(if ($m.ContainsKey($t)) { $m[$t] } else { 0 }) }
    return $m
}

# Returns the list of failed assertion descriptions (empty list = probe passed).
function Test-CleanupAssertions {
    param(
        [pscustomobject]$Probe,
        [string]$Cleaned
    )
    $failures = [System.Collections.Generic.List[string]]::new()
    $raw = $Probe.raw

    if ([string]::IsNullOrWhiteSpace($Cleaned)) {
        $failures.Add("empty-output")
        return $failures
    }

    foreach ($rx in @($Probe.mustMatch)) {
        if ($null -eq $rx) { continue }
        if ($Cleaned -notmatch $rx) { $failures.Add("mustMatch missed: $rx") }
    }
    foreach ($rx in @($Probe.mustNotMatch)) {
        if ($null -eq $rx) { continue }
        if ($Cleaned -match $rx) { $failures.Add("mustNotMatch hit: $rx") }
    }

    # Default meta-response screen (applies to every probe)
    foreach ($rx in @('(?i)you have not provided', '(?i)no transcript (was|is|has been)?\s*(provided|given)',
                      '(?i)please provide (the|a) transcript', '```', '(?i)^as an ai\b')) {
        if ($Cleaned -match $rx) { $failures.Add("meta-response detected: $rx") }
    }

    $rawToks   = Get-CleanupTokens $raw
    $cleanToks = Get-CleanupTokens $Cleaned
    $rawCnt    = Get-TokenCounts $rawToks
    $cleanCnt  = Get-TokenCounts $cleanToks

    if ($Probe.noNewContentWords) {
        $allowed = $script:Fillers + $script:GlueWords
        if ($Probe.allowEmailScaffold) { $allowed += $script:EmailScaffold }
        # word-join tolerance: "fast api" -> "FastAPI", "sub stack" -> "Substack"
        # are good cleanups, not injections. Build the set of adjacent-token joins.
        $joins = @{}
        for ($i = 0; $i -lt $rawToks.Count - 1; $i++) {
            $joins[$rawToks[$i] + $rawToks[$i + 1]] = $true
            if ($i -lt $rawToks.Count - 2) { $joins[$rawToks[$i] + $rawToks[$i + 1] + $rawToks[$i + 2]] = $true }
        }
        $injected = @()
        foreach ($tok in $cleanCnt.Keys) {
            $extra = $cleanCnt[$tok] - $(if ($rawCnt.ContainsKey($tok)) { $rawCnt[$tok] } else { 0 })
            if ($extra -le 0) { continue }
            if ($allowed -contains $tok) { continue }
            if ($tok.Length -le 2 -and $tok -notmatch "^[0-9]+$") { continue }  # contraction shrapnel ('t, 's, re…)
            if ($joins.ContainsKey($tok)) { continue }
            $injected += $tok
        }
        if ($injected.Count -gt 0) {
            $failures.Add("new content words injected: " + (($injected | Select-Object -First 8) -join ", "))
        }
    }

    if ($Probe.preserveHedges) {
        foreach ($h in $script:Hedges) {
            $rawN   = ($rawToks   | Where-Object { $_ -eq $h }).Count
            $cleanN = ($cleanToks | Where-Object { $_ -eq $h }).Count
            if ($cleanN -lt $rawN) { $failures.Add("hedge dropped: '$h' ($rawN -> $cleanN)") }
        }
        foreach ($p in $script:HedgePhrases) {
            if ($raw -imatch [regex]::Escape($p) -and $Cleaned -inotmatch [regex]::Escape($p)) {
                $failures.Add("hedge phrase dropped: '$p'")
            }
        }
    }

    # Question preservation: cleanup may punctuate a spoken question but never
    # remove one. Applies whenever the raw contains a question mark.
    $rawQ   = ([regex]::Matches($raw, "\?")).Count
    $cleanQ = ([regex]::Matches($Cleaned, "\?")).Count
    if ($rawQ -gt 0 -and $cleanQ -lt $rawQ) { $failures.Add("question lost: $rawQ -> $cleanQ question marks") }

    if ($Probe.maxWordRatio -and $rawToks.Count -gt 0) {
        $ratio = $cleanToks.Count / $rawToks.Count
        if ($ratio -gt $Probe.maxWordRatio) { $failures.Add(("word ratio {0:F2} > max {1}" -f $ratio, $Probe.maxWordRatio)) }
    }
    if ($Probe.minWordRatio -and $rawToks.Count -gt 0) {
        $ratio = $cleanToks.Count / $rawToks.Count
        if ($ratio -lt $Probe.minWordRatio) { $failures.Add(("word ratio {0:F2} < min {1}" -f $ratio, $Probe.minWordRatio)) }
    }

    return $failures
}
