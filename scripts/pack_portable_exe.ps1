# Impacchetta un bundle Flutter Windows in un singolo exe portabile tramite
# Enigma Virtual Box. Impostare ENIGMA_VB_PATH se enigmavbconsole.exe non si
# trova nel PATH o nelle cartelle Program Files standard.

param(
    [Parameter(Mandatory = $true)][string]$ReleaseDir,
    [Parameter(Mandatory = $true)][string]$MainExeName,
    [Parameter(Mandatory = $true)][string]$OutputExe
)

$ErrorActionPreference = "Stop"

function Find-EnigmaConsole {
    if ($env:ENIGMA_VB_PATH -and
        (Test-Path -LiteralPath $env:ENIGMA_VB_PATH -PathType Leaf)) {
        return $env:ENIGMA_VB_PATH
    }

    $candidates = @(
        (Join-Path $env:ProgramFiles "Enigma Virtual Box\enigmavbconsole.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Enigma Virtual Box\enigmavbconsole.exe")
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }

    $command = Get-Command enigmavbconsole.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    return $null
}

function ConvertTo-XmlText([string]$Text) {
    return [System.Security.SecurityElement]::Escape($Text)
}

function Get-FilesXml([string]$Directory) {
    $builder = New-Object System.Text.StringBuilder
    Get-ChildItem -LiteralPath $Directory | Sort-Object Name | ForEach-Object {
        $name = ConvertTo-XmlText $_.Name
        if ($_.PSIsContainer) {
            $null = $builder.AppendLine("<File><Type>3</Type><Name>$name</Name><Action>0</Action><OverwriteDateTime>false</OverwriteDateTime><OverwriteAttributes>false</OverwriteAttributes><Files>")
            $null = $builder.Append((Get-FilesXml $_.FullName))
            $null = $builder.AppendLine("</Files></File>")
        }
        else {
            $fullPath = ConvertTo-XmlText $_.FullName
            $null = $builder.AppendLine("<File><Type>2</Type><Name>$name</Name><File>$fullPath</File><ActiveX>false</ActiveX><ActiveXInstall>false</ActiveXInstall><Action>0</Action><OverwriteDateTime>false</OverwriteDateTime><OverwriteAttributes>false</OverwriteAttributes><PassCommandLine>false</PassCommandLine></File>")
        }
    }
    return $builder.ToString()
}

$enigma = Find-EnigmaConsole
if (-not $enigma) {
    Write-Warning "Enigma Virtual Box non trovato. Installarlo oppure impostare ENIGMA_VB_PATH con il percorso di enigmavbconsole.exe."
    exit 1
}

$resolvedReleaseDir = (Resolve-Path -LiteralPath $ReleaseDir).Path
$mainExe = Join-Path $resolvedReleaseDir $MainExeName
if (-not (Test-Path -LiteralPath $mainExe -PathType Leaf)) {
    throw "Eseguibile principale non trovato: $mainExe"
}

$outputDir = Split-Path -Parent $OutputExe
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$entries = Get-ChildItem -LiteralPath $resolvedReleaseDir |
    Where-Object { $_.FullName -ne $mainExe } |
    Sort-Object Name |
    ForEach-Object {
        $name = ConvertTo-XmlText $_.Name
        if ($_.PSIsContainer) {
            "<File><Type>3</Type><Name>$name</Name><Action>0</Action><OverwriteDateTime>false</OverwriteDateTime><OverwriteAttributes>false</OverwriteAttributes><Files>" +
                (Get-FilesXml $_.FullName) + "</Files></File>"
        }
        else {
            $fullPath = ConvertTo-XmlText $_.FullName
            "<File><Type>2</Type><Name>$name</Name><File>$fullPath</File><ActiveX>false</ActiveX><ActiveXInstall>false</ActiveXInstall><Action>0</Action><OverwriteDateTime>false</OverwriteDateTime><OverwriteAttributes>false</OverwriteAttributes><PassCommandLine>false</PassCommandLine></File>"
        }
    }
$entriesXml = $entries -join "`r`n"

$projectXml = @"
<?xml encoding="utf-16"?>
<>
	<InputFile>$(ConvertTo-XmlText $mainExe)</InputFile>
	<OutputFile>$(ConvertTo-XmlText $OutputExe)</OutputFile>
	<Files>
		<Enabled>true</Enabled>
		<DeleteExtractedOnExit>true</DeleteExtractedOnExit>
		<CompressFiles>true</CompressFiles>
		<Files>
			<File>
				<Type>3</Type>
				<Name>%DEFAULT FOLDER%</Name>
				<Action>0</Action>
				<OverwriteDateTime>false</OverwriteDateTime>
				<OverwriteAttributes>false</OverwriteAttributes>
				<Files>
$entriesXml
				</Files>
			</File>
		</Files>
	</Files>
	<Registries>
		<Enabled>false</Enabled>
		<Registries>
			<Registry><Type>1</Type><Virtual>true</Virtual><Name>Classes</Name><ValueType>0</ValueType><Value/><Registries/></Registry>
			<Registry><Type>1</Type><Virtual>true</Virtual><Name>User</Name><ValueType>0</ValueType><Value/><Registries/></Registry>
			<Registry><Type>1</Type><Virtual>true</Virtual><Name>Machine</Name><ValueType>0</ValueType><Value/><Registries/></Registry>
			<Registry><Type>1</Type><Virtual>true</Virtual><Name>Users</Name><ValueType>0</ValueType><Value/><Registries/></Registry>
			<Registry><Type>1</Type><Virtual>true</Virtual><Name>Config</Name><ValueType>0</ValueType><Value/><Registries/></Registry>
		</Registries>
	</Registries>
	<Packaging><Enabled>false</Enabled></Packaging>
	<Options>
		<ShareVirtualSystem>true</ShareVirtualSystem>
		<MapExecutableWithTemporaryFile>false</MapExecutableWithTemporaryFile>
		<AllowRunningOfVirtualExeFiles>false</AllowRunningOfVirtualExeFiles>
	</Options>
</>
"@

$projectFile = Join-Path ([System.IO.Path]::GetTempPath()) "esp_loader_portable.evb"
Set-Content -LiteralPath $projectFile -Value $projectXml -Encoding Unicode

Write-Host "Packaging con Enigma Virtual Box: $OutputExe" -ForegroundColor Cyan
& $enigma $projectFile
if ($LASTEXITCODE -ne 0) {
    throw "enigmavbconsole ha restituito il codice $LASTEXITCODE."
}

Write-Host "Packaging completato: $OutputExe" -ForegroundColor Green
