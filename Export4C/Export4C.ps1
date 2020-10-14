# Export4C by Ratin (knsoft.org)

<#
.SYNOPSIS
Export4C is a kit work as a build step calculates and exports actual address and size of each function in C source,
and can be referenced by other sources in the project.
.PARAMETER Source
Path to the C source.
.PARAMETER IntDir
The directory Export4C works at. Contains both of assembly listing file and object file,
outputted by MSVC compiler, corresponding to specified C source in Source parameter.
By default, this directory is $(IntDir) in Visual Studio variables.
.PARAMETER NoLogo
Suppresses startup banner and messages for successful assembly.
.PARAMETER DebugBuild
Passes /Zi and /Zd parameters to MASM, they will not be passed by default.
.PARAMETER NoSafeSEH
Does not pass /SAFESEH parameter to MASM for x86 build, it will be passed by default.
.LINK
https://knsoft.org/Prod/Export4C
.LINK
https://github.com/KNSoft/Export4C
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $True)]
    [String]
    $Source,
    [Parameter(Mandatory = $True)]
    [String]
    $IntDir,
    [Switch]
    $NoLogo,
    [Switch]
    $DebugBuild,
    [Switch]
    $NoSafeSEH
)

# === Pre-definations ===

[String]$E4C_Version = '1.0.0.0 Alpha'
[Char[]]$HexChars = '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'

Function E4C_Msg_Error([Int32] $Code, [String]$Msg) {
    $host.UI.WriteErrorLine('Export4C: fatal error EC' + $Code.ToString('D3') + ': ' + $Msg)
}

Function E4C_Str_WordBefore([String]$Text, [String]$Word) {
    If (($Text.Length -gt $Word.Length) -and $Text.EndsWith($Word) -and [Char]::IsWhiteSpace($Text[$Text.Length - $Word.Length - 1])) {
        Return $Text.Remove($Text.Length - $Word.Length).TrimEnd()
    } Else {
        Return [String]::Empty
    }
}

Function E4C_Str_Middle([String]$Text, [String]$StartWord, [String]$EndWord) {
    [Int32]$SubLength = $Text.Length - $StartWord.Length - $EndWord.Length
    If (($SubLength -gt 0) -and $Text.StartsWith($StartWord) -and $Text.EndsWith($EndWord)) {
        Return $Text.Substring($StartWord.Length, $SubLength)
    } Else {
        Return [String]::Empty
    }
}

Function E4C_Str_WordAfter([String]$Text, [String]$Word) {
    If (($Text.Length -gt $Word.Length) -and $Text.StartsWith($Word) -and [Char]::IsWhiteSpace($Text[$Word.Length])) {
        Return $Text.Substring($Word.Length).TrimStart()
    } Else {
        Return [String]::Empty
    }
}

If (-not $NoLogo) {
    'KNSoft Export4C Version ' + $E4C_Version
    ''
}

# === Confirm file inputs and outputs ===

# Verify IntDir and append backslash if it hasn't
If (-not (Test-Path $IntDir -PathType Container)) {
    E4C_Msg_Error -Code 1 -Msg "IntDir not exists ($($Source))"
    Exit 1
}
If (-not $IntDir.EndsWith('\')) {
    $IntDir = $IntDir.Insert($IntDir.Length, '\')
}
# Verify Source and get file name
If (-not (Test-Path $Source -PathType Leaf)) {
    E4C_Msg_Error -Code 2 -Msg "Source not exists ($($Source))"
    Exit 1
}
[String]$FileName = $Source.Remove($Source.LastIndexOf('.')) 
# Both of ASM listing file and object file are required in IntDir
[String]$ASMListFile = [String]::Empty
'asm', 'cod' | ForEach-Object {
    [String]$TempASMListFile = $IntDir + $FileName + '.' + $_
    If ((-not $ASMListFile) -and (Test-Path $TempASMListFile -PathType Leaf)) {
        $ASMListFile = $TempASMListFile
    }
}
If (-not $ASMListFile) {
    E4C_Msg_Error -Code 3 -Msg "ASM listing file ($($FileName).asm or $($FileName).cod) not found in IntDir, make sure MSVC compiler generated ASM listing file output and whole program optimization was turned off"
    Exit 1
}
[String]$ObjectFile = $IntDir + $FileName + '.obj'
If (-not (Test-Path $ObjectFile -PathType Leaf)) {
    E4C_Msg_Error -Code 4 -Msg "Object file ($($ObjectFile)) not found in IntDir"
    Exit 1
}
# Catch path of new file
[String]$NewASMListing = $IntDir + $FileName + '_E4C.asm'
[String]$NewObjectFile = $IntDir + $FileName + '_E4C.obj'

# === Process C source file ===

[String[]]$IncludeLib = @()
Get-Content -Path $Source | ForEach-Object {
    [String]$LineText = $_.ToString().TrimStart()
    If ($LineText.StartsWith('#')) {
        $LineText = $LineText.Substring(1).TrimStart()
        If ($LineText.StartsWith('pragma')) {
            $LineText = $LineText.Substring(6).TrimStart()
            If ($LineText.StartsWith('comment')) {
                $LineText = $LineText.Substring(7).TrimStart()
                If ($LineText -cmatch '^\(\s*lib\s*,\s*"(.+)"\s*\)$') {
                    $IncludeLib += $Matches[1]
                }
            }
        }
    }
}

# === Process ASM listing file ===

[String]$RndPrefix = 'E4C_' + [String]::Join('', (Get-Random -InputObject $HexChars -Count 8))

# Create new ASM source
$null = New-Item -Path $NewASMListing -ItemType File -Force
If (!$?) {
    E4C_Msg_Error -Code 5 -Msg "Create new ASM source ($($NewASMListing)) failed"
    Exit 1
}
Add-Content -Path $NewASMListing -Value ('; Rewritten by Export4C ' + $E4C_Version)

# x86 and x64 have different SIZE_T, and exports have "_" prefix in x86
[Int32]$PlatformBits = 0
[String]$SizeTDefine = [String]::Empty
[String]$SymbolPrefix = [String]::Empty

[Boolean]$AssumeNothing = $False;
[Boolean]$AppendLib = $False;

# Procedure name and symbol name in PROC area
[String]$SegName = [String]::Empty
[String]$SymbolName = [String]::Empty
[String]$ProcName = [String]::Empty

# Store procedure names to add exports
[String[]]$ExpProcs = @()

# Read per line of assembly listing file
Get-Content -Path $ASMListFile | ForEach-Object {
    [String]$LineText = $_.ToString()
    [String[]]$InsertBefore = @()
    [String[]]$InsertAfter = @()
    [Boolean]$Delete = $False
    [Boolean]$Modified = $False
    [String]$TrimedText = $LineText.TrimStart().TrimEnd()
    # Trim comment and ignore empty line
    [Int32]$CommentPos = $TrimedText.IndexOf(';')
    If ($CommentPos -gt 0) {
        $TrimedText = $TrimedText.Remove($CommentPos).TrimEnd()
    }
    # Remove "FLAT:" at first
    [Int32]$FlatPos = $TrimedText.IndexOf('FLAT:')
    If (($FlatPos -gt 0) -and [Char]::IsWhiteSpace($TrimedText[$FlatPos - 1])) {
        $TrimedText = $TrimedText.Remove($FlatPos, 5)
        $Modified = $True
    }
    If ($TrimedText.Length -eq 0) {
        Add-Content -Path $NewASMListing -Value $LineText
        Return
    }
    # Recognize x64 or x86 at first, according to ".686P" before "include listing.inc"
    If (-not $PlatformBits) {
        If ($TrimedText.Equals('.686P')) {
            $PlatformBits = 32
            $SizeTDefine = 'DD'
            $SymbolPrefix = '_'
        } ElseIf ($TrimedText.Equals('include listing.inc')) {
            $PlatformBits = 64
            $SizeTDefine = 'DQ'
        }
    }
    # Add "ASSUME NOTHING" statement for using segment registers in x86
    If (($PlatformBits -eq 32) -and (-not $AssumeNothing) -and $TrimedText.Equals(".model`tflat")) {
        $InsertAfter += 'ASSUME NOTHING'
        $AssumeNothing = $True
    }
    # Append library including
    If ((-not $AppendLib) -and ($IncludeLib.Count -gt 0) -and $TrimedText.Equals('include listing.inc')) {
        $IncludeLib | ForEach-Object {
            $InsertAfter += 'INCLUDELIB ' + $_
        }
        $AppendLib = $True
    }
    # Process the line
    If ($PlatformBits) {
        [String]$TempStr = [String]::Empty
        [Int32]$TempPos = 0

        If (-not $SegName) {
            # Recognize current segment
            $TempStr = E4C_Str_WordBefore -Text $TrimedText -Word 'SEGMENT'
            If ($TempStr) {
                $SegName = $TempStr
            }
            $TempStr = E4C_Str_WordAfter -Text $TrimedText -Word 'PUBLIC'
            # Found symbol exports
            If ($TempStr) {
                # Remove __real@ symbol exports
                If ($TempStr.StartsWith('__real@') -and (-not ($TempStr.Substring(7).ToUpper().ToCharArray() | Where-Object { -not $HexChars.Contains($_) }))) {
                    $Delete = $True
                }
                # Remove "__local_*" symbol exports, although procedures are always public
                ElseIf ($TempStr.StartsWith($SymbolPrefix + '__local_')) {
                    $Delete = $True
                }
                # Remove "___JustMyCode_Default" symbol
                ElseIf ($TempStr.Equals('__JustMyCode_Default')) {
                    $Delete = $True
                }
            }
            # Found end of file, add exports before it
            ElseIf ($TrimedText.Equals('END') -and ($ExpProcs.Count -gt 0)) {
                $ExpProcs | ForEach-Object {
                    $InsertBefore += ("PUBLIC $($SymbolPrefix)E4C_Addr_" + $_), ("PUBLIC $($SymbolPrefix)E4C_Size_" + $_)
                }
                $InsertBefore += 'CONST	SEGMENT'
                $ExpProcs | ForEach-Object {
                    $InsertBefore += ($SymbolPrefix + "E4C_Addr_$($_) $($SizeTDefine) OFFSET E4C_Start_$($_)"), ($SymbolPrefix + "E4C_Size_$($_) $($SizeTDefine) OFFSET E4C_End_$($_) - OFFSET E4C_Start_$($_)")
                }
                $InsertBefore += 'CONST	ENDS'
            }
        } Else {
            If ($SegName.Equals('_TEXT')) {
                If (-not $SymbolName) {
                    # Find start of procedure
                    $TempStr = E4C_Str_WordBefore -Text $TrimedText -Word 'PROC'
                    If ($TempStr) {
                        $SymbolName = $TempStr
                        If ($PlatformBits -eq 64) {
                            $ProcName = $SymbolName
                        } Else {
                            $ProcName = $SymbolName.Split('@')[0].Substring(1)
                        }
                        # Fix "__local_*" function conflicts with MSVCRT library and JMC function conflicts with other modules
                        If ($TempStr.StartsWith("$($SymbolPrefix)__local_") -or $TempStr.Equals('__JustMyCode_Default')) {
                            $TempStr = $RndPrefix + $TempStr
                            $InsertAfter += $TempStr + "`tProc"
                            $Delete = $True
                        } Else {
                            $InsertBefore += "E4C_Start_$($ProcName):"
                        }
                    }
                } Else {
                    # Find end of procedure
                    $TempStr = E4C_Str_WordBefore -Text $TrimedText -Word 'ENDP'
                    If ($TempStr) {
                        # Fix "__local_*" function conflicts with MSVCRT library and JMC function conflicts with other modules
                        If ($TempStr.StartsWith("$($SymbolPrefix)__local_") -or $TempStr.Equals('__JustMyCode_Default')) {
                            $TempStr = $RndPrefix + $TempStr
                            $InsertAfter += $TempStr + "`tENDP"
                            $Delete = $True
                        } Else {
                            $InsertAfter += 'E4C_End_' + $ProcName + ':'
                            $ExpProcs += $ProcName
                        }
                        $SymbolName = [String]::Empty
                        $ProcName = [String]::Empty
                    } Else {
                        # Fix the short jumps may be too far
                        $TempPos = $TrimedText.IndexOf("`tSHORT ")
                        If ($TempPos -gt 0) {
                            $InsertAfter += $TrimedText.Remove($TempPos + 1, 6)
                            $Delete = $True
                        }
                        # Fix "__local_*" function conflicts with MSVCRT library
                        ElseIf ($TrimedText.StartsWith("call`t$($SymbolPrefix)__local_")) {
                            $InsertAfter += $TrimedText.Insert(5, $RndPrefix)
                            $Delete = $True
                        } ElseIf ($PlatformBits -eq 64) {
                            # In x64, fix "$LN*:" backward reference error and redefination error in pdata segment
                            $TempStr = E4C_Str_Middle -Text $TrimedText -StartWord '$LN' -EndWord ':'
                            If ($TempStr) {
                                If (-not ($TempStr.ToCharArray() | Where-Object { -not [Char]::IsNumber($_) })) {
                                    $InsertAfter += '$LN' + $TempStr + '@' + $SymbolName + '::'
                                    $Delete = $True
                                }
                            }
                            # Fix "gs:Num" to "gs:[Num]"
                            ElseIf (($TrimedText.IndexOf('gs') -gt 0) -and ($TrimedText -cmatch '^(.+)\s+gs\s*:\s*(\d+)(.*)$')) {
                                $InsertAfter += $Matches[1] + ' gs:[' + $Matches[2] + ']' + $Matches[3]
                                $Delete = $True
                            }
                        }
                    }
                }
            } ElseIf ($SegName.Equals('pdata')) {
                # In x64, fix "$LN*:" backward reference error and redefination error in pdata segment
                If ($TrimedText -cmatch '^\$pdata\$(\S+)\s+DD\s+imagerel\s+\$LN(\d+)$') {
                    $ProcName = $Matches[1]
                    If ($ProcName.StartsWith("$($SymbolPrefix)__local_")) {
                        $ProcName = $RndPrefix + $ProcName
                    }
                    $InsertAfter += '$pdata$' + $ProcName + ' DD imagerel $LN' + $Matches[2] + '@' + $ProcName
                    $Delete = $True
                } ElseIf ($TrimedText -cmatch '^DD\s+imagerel\s+\$LN(\d+)(.*)$') {
                    $InsertAfter += 'DD imagerel $LN' + $Matches[1] + '@' + $ProcName + $Matches[2]
                    $Delete = $True
                }
            }
            # Fix "." in RTC segment
            ElseIf ($SegName.Equals('rtc$TMZ')) {
                If ($TrimedText.Equals($SymbolPrefix + '_RTC_Shutdown.rtc$TMZ ' + $SizeTDefine + ' ' + $SymbolPrefix + '_RTC_Shutdown')) {
                    $InsertAfter += $SymbolPrefix + '_RTC_Shutdown_rtc$TMZ ' + $SizeTDefine + ' ' + $SymbolPrefix + '_RTC_Shutdown'
                    $Delete = $True
                }
            } ElseIf ($SegName.Equals('rtc$IMZ')) {
                If ($TrimedText.Equals($SymbolPrefix + '_RTC_InitBase.rtc$IMZ ' + $SizeTDefine + ' ' + $SymbolPrefix + '_RTC_InitBase')) {
                    $InsertAfter += $SymbolPrefix + '_RTC_InitBase_rtc$TMZ ' + $SizeTDefine + ' ' + $SymbolPrefix + '_RTC_InitBase'
                    $Delete = $True
                }
            }
            # Ends current segment
            If ($TrimedText.Equals($SegName + "`tENDS")) {
                $SegName = [String]::Empty
            }
        }
    }
    # Append to output
    $InsertBefore | ForEach-Object {
        Add-Content -Path $NewASMListing -Value ($_ + ' ; Export4C adds')
    }
    If ($Delete) {
        Add-Content -Path $NewASMListing -Value (' ; ' + $LineText + ' ; Export4C deletes')
    } ElseIf ($Modified) {
        Add-Content -Path $NewASMListing -Value (' ; ' + $LineText + ' ; Export4C deletes')
        Add-Content -Path $NewASMListing -Value ($TrimedText + ' ; Export4C adds')
    } Else {
        Add-Content -Path $NewASMListing -Value $LineText
    }
    $InsertAfter | ForEach-Object {
        Add-Content -Path $NewASMListing -Value ($_ + ' ; Export4C adds')
    }
}

# === Assemble new source ===
[String]$MASM = [String]::Empty
[String[]]$MASMParam = '/c', '/nologo', '/W3'
If ($PlatformBits -eq 32) {
    $MASM = 'ml.exe'
    If (-not $NoSafeSEH) {
        $MASMParam += '/safeseh'
    }
} Else {
    $MASM = 'ml64.exe'
}
If ($DebugBuild) {
    $MASMParam += '/Zi', '/Zd'
}
$MASMParam += "/Fo`"$($NewObjectFile)`"", "/Ta`"$($NewASMListing)`""

$MLProc = Start-Process -FilePath $MASM -ArgumentList $MASMParam -NoNewWindow -Wait -PassThru
If ($MLProc.ExitCode -eq 0) {
    Move-Item -Path $NewObjectFile -Destination $ObjectFile -Force
    If ($?) {
        Exit 0
    } Else {
        E4C_Msg_Error -Code 6 -Msg 'Overwrite original object file failed'
        Exit 1
    }
} Else {
    E4C_Msg_Error -Code 7 -Msg 'MASM assembling failed'
    Exit $MLProc.ExitCode
}