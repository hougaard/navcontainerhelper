﻿<# 
 .Synopsis
  Uses a Nav Container to signs a Nav App
 .Description
  appFile must be shared with the container
  Copies the pfxFile to the container if necessary
  Creates a session to the Nav container and Signs the App using the provided certificate and password
 .Parameter containerName
  Name of the container in which you want to publish an app (default is navserver)
 .Parameter appFile
  Path of the app you want to sign
 .Parameter pfxFile
  Path/Url of the certificate pfx file to use for signing
 .Parameter pfxPassword
  Password of the certificate pfx file
 .Example
  Sign-NavContainerApp -appFile c:\programdata\navcontainerhelper\myapp.app -pfxFile http://my.secure.url/mycert.pfx -pfxPassword $securePassword
 .Example
  Sign-NavContainerApp -appFile c:\programdata\navcontainerhelper\myapp.app -pfxFile c:\programdata\navcontainerhelper\mycert.pfx -pfxPassword $securePassword
#>
function Sign-NavContainerApp {
    Param(
        [string]$containerName = "navserver",
        [Parameter(Mandatory=$true)]
        [string]$appFile,
        [string]$pfxFile,
        [SecureString]$pfxPassword
    )

    $containerAppFile = Get-NavContainerPath -containerName $containerName -path $appFile
    if ("$containerAppFile" -eq "") {
        throw "The app ($appFile)needs to be in a folder, which is shared with the container $containerName"
    }

    $copied = $false
    if ($pfxFile.ToLower().StartsWith("http://") -or $pfxFile.ToLower().StartsWith("https://")) {
        $containerPfxFile = $pfxFile
    } else {
        $containerPfxFile = Get-NavContainerPath -containerName $containerName -path $pfxFile
        if ("$containerPfxFile" -eq "") {
            $containerPfxFile = Join-Path "c:\run" ([System.IO.Path]::GetFileName($pfxFile))
            Copy-FileToNavContainer -containerName $containerName -localPath $pfxFile -containerPath $containerPfxFile
            $copied = $true
        }
    }


    $session = Get-NavContainerSession -containerName $containerName -silent
    Invoke-Command -Session $session -ScriptBlock { Param($appFile, $pfxFile, $pfxPassword)

        if ($pfxFile.ToLower().StartsWith("http://") -or $pfxFile.ToLower().StartsWith("https://")) {
            $pfxUrl = $pfxFile
            $pfxFile = Join-Path "c:\run" ([System.Uri]::UnescapeDataString([System.IO.Path]::GetFileName($pfxUrl).split("?")[0]))
            (New-Object System.Net.WebClient).DownloadFile($pfxUrl, $pfxFile)
            $copied = $true
        }

        if (Test-Path "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\SignTool.exe") {
            $signToolExe = (get-item "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\SignTool.exe").FullName
        } else {
            Write-Host "Downloading Signing Tools"
            $winSdkSetupExe = "c:\run\install\winsdksetup.exe"
            $winSdkSetupUrl = "https://go.microsoft.com/fwlink/p/?LinkID=2023014"
            (New-Object System.Net.WebClient).DownloadFile($winSdkSetupUrl, $winSdkSetupExe)
            Write-Host "Installing Signing Tools"
            Start-Process $winSdkSetupExe -ArgumentList "/features OptionId.SigningTools /q" -Wait
            if (!(Test-Path "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\SignTool.exe")) {
                throw "Cannot locate signtool.exe after installation"
            }
            $signToolExe = (get-item "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\SignTool.exe").FullName
        }

        Write-Host "Signing $appFile"
        $unsecurepassword = ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pfxPassword)))
        & "$signtoolexe" @("sign", "/f", "$pfxFile", "/p","$unsecurepassword", "/t", "http://timestamp.verisign.com/scripts/timestamp.dll", "$appFile") | Write-Host

        if ($copied) { 
            Remove-Item $pfxFile -Force
        }
    } -ArgumentList $containerAppFile, $containerPfxFile, $pfxPassword
}
Export-ModuleMember -Function Sign-NavContainerApp
