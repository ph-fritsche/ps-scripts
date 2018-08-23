<#
## PS-tool for easier management of %PATH%
##
## @Author Philipp Fritsche <ph.fritsche@gmail.com>
## @License MIT
#>

function main {

    $IsRunAsAdmin = isRunAsAdmin
    if (!$IsRunAsAdmin) {
        Write-Host ""
        Write-Host ""
        Write-Host "Note: Manipulating machine-wide environment requires administrator privileges."
    }

    do {
        Write-Host ""
        Write-Host ""
        Write-Host "Current Path"

        $machinePaths = getMachinePath
        Write-Host "--Machine"
        $machinePaths | printPath 0 $IsRunAsAdmin | Write-Host

        $userPaths = getUserPath
        if ($IsRunAsAdmin) {
            $userPathsOffset = $machinePaths.Length
        } else {
            $userPathsOffset = 0
        }
        Write-Host "--User"
        $userPaths | printPath $userPathsOffset | Write-Host

        Write-Host ""
        $action = askChoice "Which action would you like to perform? (Enter nothing to quit)" @("add","remove","move")

        if ($action -eq "") {

            Write-Host "Do nothing - Bye!"
            exit 0

        } elseif ($action -eq "add") {

            $path = askPath "Which path would you like to add?"
            if ($path -eq "" -or $path -eq $null) {
                "Nothing selected - Cancel"
                continue
            }
            $normalizedPath = $path | normalizeWinPaths

            if (!$IsRunAsAdmin) {
                $target = "user"
            } else {
                $target = askChoice "Where do you want to add the path?" @("machine","user","both") "user"
            }

            if ($target -eq "machine" -or $target -eq "both") {
                $machinePaths = [System.Collections.ArrayList] $machinePaths
                [void] $machinePaths.Add($normalizedPath)
                setMachinePath $machinePaths
            }
            if ($target -eq "user" -or $target -eq "both") {
                $userPaths = [System.Collections.ArrayList] $userPaths
                [void] $userPaths.Add( $normalizedPath )
                setUserPath $userPaths
            }

        } elseif ($action -eq "move") {

            $pos = askInt "Which path would you like to move? (Use the numbers)"

            if ($pos -eq $null) {
                Write-Host "Cancel"
                continue
            } elseif ($pos -lt $userPathsOffset) {
                $target = "machine"
                $object = $machinePaths[$pos]
            } else {
                $target = "user"
                $pos = $pos - $userPathsOffset
                $object = $userPaths[$pos]
            }
            if ($object -eq $null) {
                Write-Host "Out of range - Cancel"
                continue
            }

            $newPos = askInt "Where should it be moved? (New position)"

            if ($newPos -eq $null) {
                Write-Host "Cancel"
                continue
            } elseif ($target -eq "machine") {
                $machinePaths = [System.Collections.ArrayList] ( $machinePaths[0..($pos-1)] + $machinePaths[($pos+1)..($machinePaths.Length)] )
                [void] $machinePaths.Insert($newPos, $object)
                setMachinePath $machinePaths
            } else {
                if ($newPos -ge $userPathsOffset) {
                    $newPos = $newPos - $userPathsOffset
                } else {
                    $newPos = 0
                }
                $userPaths = [System.Collections.ArrayList] ( $userPaths[0..($pos-1)] + $userPaths[($pos+1)..($userPaths.Length)] )
                [void] $userPaths.Insert($newPos, $object)
                setUserPath $userPaths
            }

        } elseif ($action -eq "remove") {

            $pos = askInt "Which path would you like to remove? (Use the numbers)"

            if ($pos -eq $null) {
                Write-Host "Cancel"
                continue
            } elseif ($pos -lt $userPathsOffset) {
                $target = "machine"
                $machinePaths = [System.Collections.ArrayList] $machinePaths
                [void] $machinePaths.RemoveAt($pos)
                setMachinePath $machinePaths
            } else {
                $target = "user"
                $pos = $pos - $userPathsOffset
                $userPaths = [System.Collections.ArrayList] $userPaths
                [void] $userPaths.RemoveAt($pos)
                setUserPath $userPaths
            }

        }

        $env:Path = ($machinePaths + $userPaths) -join ";"
    } while($true)

}

function isRunAsAdmin {
    # from https://serverfault.com/a/95464
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ask(
    [string] $question = "",
    [string] $default
) {
    if ($question -ne "") {
        Write-Host $question
    }
    if ($default -ne "" -and $default -ne $null) {
        $prompt = "    (default: $default)"
    } else {
        $prompt = "    "
    }
    $answer = Read-Host $prompt
    if ($answer -eq "" -or $answer -eq $null) {
        return $default
    } else {
        return $answer
    }
}

function askChoice(
    [string] $question = "",
    [string[]] $options = @("Yes", "No"),
    [string] $default
) {
    $options = $options | Sort-Object
    $realOptions = @{}
    $writeOptions = [System.Collections.ArrayList]@()
    foreach($o in $options) {
        if ($o.GetType() -ne [string] -or $o.Length -eq 0) {
            continue
        }
        $first = $o.Substring(0,1).ToLower()
        if ($first -eq "-") {
            if($o.Length -eq 1) {
                continue
            } else {
                $realOptions[$o.Substring(1)] = $o.Substring(1)
                [void] $writeOptions.Add($o.Substring(1))
            }
        } else {
            if ($realOptions[$first] -eq $null) {
                $realOptions[$first] = $o.ToLower()
                $realOptions[$o.ToLower()] = $o.ToLower()
                [void] $writeOptions.Add("[" + $first.ToUpper() + "]" + $o.Substring(1))
            } else {
                $realOptions[$o.ToLower()] = $o.ToLower()
                [void] $writeOptions.Add($o)
            }
        }
    }
    $writeOptions = "    " + ($writeOptions -join ", ")
    if ($default -ne "") {
        $writeOptions += " (default: " + $default + ")"
    }
    do {
        if ($question -ne "") {
            Write-Host $question
        }
        $host.UI.RawUI.FlushInputBuffer()
        $choice = Read-Host $writeOptions
        if ($choice -eq "" -or $choice -eq $null) {
            return $default
        } elseif ($realOptions[$choice] -ne $null) {
            return $realOptions[$choice]
        } else {
            Write-Host "    Invalid choice"
        }
    } while ($true)
}

function askPath(
    [string] $question = "",
    [string] $default = "",
    [string] $pathType = "Container"
) {
    $path = ask $question $default
    if ($path -eq "") {
        return $default
    }
    if (! (Test-Path $path -PathType $pathType)) {
        $confirm = askChoice "'$path' is no directory - Are you sure?" @("cancel", "back", "yes") "back"
        if ($confirm -eq "cancel") {
            return $null
        } elseif ($confirm -eq "back") {
            $path = askPath $question $path
        }
    }
    $path
}

function askInt(
    [string] $question = "",
    [string] $default = ""
) {
    (ask $question $default) -as [int]
}

function getPath (
    $target
) {
    $unique = [System.Collections.ArrayList]@()
    $path = [Environment]::GetEnvironmentVariable("Path", $target)
    $path = $path.Split(";") | normalizeWinPaths
    foreach ($p in $path) {
        if (! $unique.Contains($p)) {
            [void] $unique.Add($p)
        }
    }
    $unique
}

function getMachinePath {
    getPath ([System.EnvironmentVariableTarget]::Machine)
}

function getUserPath {
    getPath ([System.EnvironmentVariableTarget]::User)
}

function normalizeWinPaths {
    foreach ($path in $input) {
        if (!$path) { continue }
        $path = $path.replace("/","\").ToLower()
        $normalized = [System.Collections.ArrayList]@()
        $domainMatch = ($path | Select-String -Pattern "^([a-z]:\\?|\\\\[^\\]+\\?|\\)").Matches
        if ($domainMatch.count) {
            $domain = $domainMatch[0].Value
            $path = $path.Substring($domainMatch[0].Length)
        } else {
            $domain = ".\"
        }
        foreach ($seg in $path.Split("\")) {
            if ($seg -eq "" -or $seg -eq ".") {
                continue
            } elseif ($seg -eq ".." -and $normalized.Count -gt 0 -and $normalized[-1] -ne "..") {
                [void] $normalized.RemoveAt($normalized.Count -1)
            } else {
                [void] $normalized.Add($seg)
            }
        }
        $domain + ($normalized -join "\")
    }
}

function printPath(
    [int] $offset = 0,
    [bool] $index = $true
) {
    $print = [System.Collections.ArrayList]@()
    foreach ($p in $input) {
        if (!$index) {
            $out = "  " + $p
        } else {
            $out = " (" + ([string]$offset).PadLeft(2, " ") + ") " + $p
        }
        [void] $print.Add( $out )
        $offset++
    }
    $print
}

function setPath(
    [string[]] $list,
    $target
) {
    [void] [Environment]::SetEnvironmentVariable("Path", $list -join ";", $target)
}

function setMachinePath(
    [string[]] $list
) {
    setPath $list ([System.EnvironmentVariableTarget]::Machine)
}

function setUserPath(
    [string[]] $list
) {
    setPath $list ([System.EnvironmentVariableTarget]::User)
}

main
