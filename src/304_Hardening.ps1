function Get-UEFIStatus {
    <#
    .SYNOPSIS
    Helper - Gets the BIOS mode of the machine (Legacy / UEFI)

    Author: @itm4n
    License: BSD 3-Clause

    .DESCRIPTION
    Invokes the "GetFirmwareEnvironmentVariable()" function from the Windows API with dummy parameters. Indeed, the queried value doesn't matter, what matters is the last error code, which you can get by invoking "GetLastError()". If the return code is ERROR_INVALID_FUNCTION, this means that the function is not supported by the BIOS so it's LEGACY. Otherwise, the error code will indicate that it cannot find the requested variable, which means that the function is supported by the BIOS so it's UEFI.

    .EXAMPLE
    PS C:\> Get-UEFIStatus

    Name Status Description
    ---- ------ -----------
    UEFI   True BIOS mode is UEFI

    .NOTES
    https://github.com/xcat2/xcat-core/blob/master/xCAT-server/share/xcat/netboot/windows/detectefi.cpp
    https://docs.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getfirmwareenvironmentvariablea
    https://github.com/ChrisWarwick/GetUEFI/blob/master/GetFirmwareBIOSorUEFI.psm1
    #>

    [CmdletBinding()]Param()

    $OsVersion = Get-WindowsVersion

    # Windows >= 8/2012
    if (($OsVersion.Major -ge 10) -or (($OsVersion.Major -ge 6) -and ($OsVersion.Minor -ge 2))) {

        [UInt32]$FirmwareType = 0
        $Result = $Kernel32::GetFirmwareType([ref]$FirmwareType)
        $LastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

        if ($Result -gt 0) {
            if ($FirmwareType -eq 1) {
                # FirmwareTypeBios = 1
                $Status = $false
                $Description = "BIOS mode is Legacy"
            }
            elseif ($FirmwareType -eq 2) {
                # FirmwareTypeUefi = 2
                $Status = $true
                $Description = "BIOS mode is UEFI"
            }
            else {
                $Description = "BIOS mode is unknown"
            }
        }
        else {
            Write-Verbose ([ComponentModel.Win32Exception] $LastError)
        }

    # Windows = 7/2008 R2
    }
    elseif (($OsVersion.Major -eq 6) -and ($OsVersion.Minor -eq 1)) {

        $null = $Kernel32::GetFirmwareEnvironmentVariable("", "{00000000-0000-0000-0000-000000000000}", [IntPtr]::Zero, 0)
        $LastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

        $ERROR_INVALID_FUNCTION = 1
        if ($LastError -eq $ERROR_INVALID_FUNCTION) {
            $Status = $false
            $Description = "BIOS mode is Legacy"
            Write-Verbose ([ComponentModel.Win32Exception] $LastError)
        }
        else {
            $Status = $true
            $Description = "BIOS mode is UEFI"
            Write-Verbose ([ComponentModel.Win32Exception] $LastError)
        }

    }
    else {
        $Description = "Cannot check BIOS mode"
    }

    $Result = New-Object -TypeName PSObject
    $Result | Add-Member -MemberType "NoteProperty" -Name "Name" -Value "UEFI"
    $Result | Add-Member -MemberType "NoteProperty" -Name "Status" -Value $Status
    $Result | Add-Member -MemberType "NoteProperty" -Name "Description" -Value $Description
    $Result
}

function Get-SecureBootStatus {
    <#
    .SYNOPSIS
    Helper - Get the status of Secure Boot (enabled/disabled/unsupported)

    Author: @itm4n
    License: BSD 3-Clause

    .DESCRIPTION
    In case of a UEFI BIOS, you can check whether 'Secure Boot' is enabled by looking at the 'UEFISecureBootEnabled' value of the following registry key: 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\SecureBoot\State'.

    .EXAMPLE
    PS C:\> Get-SecureBootStatus

    Name        Status Description
    ----        ------ -----------
    Secure Boot   True Secure Boot is enabled
    #>

    [CmdletBinding()]Param()

    $RegKey = "HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\State"
    $RegValue = "UEFISecureBootEnabled"
    $RegData = (Get-ItemProperty -Path "Registry::$($RegKey)" -Name $RegValue -ErrorAction SilentlyContinue).$RegValue
    if ($null -ne $RegData) {
        if ($null -eq $RegData) {
            $Description = "Secure Boot is not supported"
        }
        else {
            if ($RegData -eq 1) {
                $Description = "Secure Boot is enabled"
            }
            else {
                $Description = "Secure Boot is disabled"
            }
        }
    }
    Write-Verbose "$($RegValue): $($Description)"
    $Result = New-Object -TypeName PSObject
    $Result | Add-Member -MemberType "NoteProperty" -Name "Key" -Value $RegKey
    $Result | Add-Member -MemberType "NoteProperty" -Name "Value" -Value $RegValue
    $Result | Add-Member -MemberType "NoteProperty" -Name "Data" -Value $(if ($null -eq $RegData) { "(null)" } else { $RegData })
    $Result | Add-Member -MemberType "NoteProperty" -Name "Description" -Value $Description
    $Result | Add-Member -MemberType "NoteProperty" -Name "Compliance" -Value $($RegData -eq 1)
    $Result
}

function Get-MachineRole {

    [CmdletBinding()] Param()

    BEGIN {
        $FriendlyNames = @{
            "WinNT"     = "Workstation";
            "LanmanNT"  = "Domain Controller";
            "ServerNT"  = "Server";
        }
    }

    PROCESS {
        $RegKey = "HKLM\SYSTEM\CurrentControlSet\Control\ProductOptions"
        $RegValue = "ProductType"
        $RegData = (Get-ItemProperty -Path "Registry::$($RegKey)" -ErrorAction SilentlyContinue).$RegValue

        $Result = New-Object -TypeName PSObject
        $Result | Add-Member -MemberType "NoteProperty" -Name "Name" -Value $RegData
        $Result | Add-Member -MemberType "NoteProperty" -Name "Role" -Value $(try { $FriendlyNames[$RegData] } catch { "" })
        $Result
    }
}

function Get-BitLockerConfiguration {
    <#
    .SYNOPSIS
    Get the BitLocker startup authentication configuration.

    Author: @itm4n
    License: BSD 3-Clause

    .DESCRIPTION
    This cmdlet retrieves information about the authentication mode used by the BitLocker configuration from the 'HKLM\Software\Policies\Microsoft\FVE' key (e.g. 'TPM only', 'TPM+PIN', etc.). 

    .EXAMPLE
    PS C:\> Get-BitLockerConfiguration

    Status             : @{Value=1; Description=BitLocker is enabled}
    UseTPM             : @{Value=1; Description=Require TPM (default)}
    UseAdvancedStartup : @{Value=0; Description=Do not require additional authentication at startup (default)}
    EnableBDEWithNoTPM : @{Value=0; Description=Do not allow BitLocker without a compatible TPM (default)}
    UseTPMPIN          : @{Value=0; Description=Do not allow startup PIN with TPM (default)}
    UseTPMKey          : @{Value=0; Description=Do not allow startup key with TPM (default)}
    UseTPMKeyPIN       : @{Value=0; Description=Do not allow startup key and PIN with TPM (default)}

    .LINK
    https://www.geoffchappell.com/studies/windows/win32/fveapi/policy/index.htm
    #>

    [CmdletBinding()] param ()

    BEGIN {
        # Default values for FVE parameters in HKLM\Software\Policies\Microsoft\FVE
        $FveConfig = @{
            UseAdvancedStartup = 0
            EnableBDEWithNoTPM = 0
            UseTPM = 1
            UseTPMPIN = 0
            UseTPMKey = 0
            UseTPMKeyPIN = 0
        }

        $FveUseAdvancedStartup = @(
            "Do not require additional authentication at startup (default)",
            "Require additional authentication at startup."
        )

        $FveEnableBDEWithNoTPM = @(
            "Do not allow BitLocker without a compatible TPM (default)",
            "Allow BitLocker without a compatible TPM"
        )

        $FveUseTPM = @(
            "Do not allow TPM",
            "Require TPM (default)",
            "Allow TPM"
        )

        $FveUseTPMPIN = @(
            "Do not allow startup PIN with TPM (default)",
            "Require startup PIN with TPM",
            "Allow startup PIN with TPM"
        )

        $FveUseTPMKey = @(
            "Do not allow startup key with TPM (default)",
            "Require startup key with TPM",
            "Allow startup key with TPM"
        )

        $FveUseTPMKeyPIN = @(
            "Do not allow startup key and PIN with TPM (default)",
            "Require startup key and PIN with TPM",
            "Allow startup key and PIN with TPM"
        )

        $FveConfigValues = @{
            UseAdvancedStartup = $FveUseAdvancedStartup
            EnableBDEWithNoTPM = $FveEnableBDEWithNoTPM
            UseTPM = $FveUseTPM
            UseTPMPIN = $FveUseTPMPIN
            UseTPMKey = $FveUseTPMKey
            UseTPMKeyPIN = $FveUseTPMKeyPIN
        }
    }

    PROCESS {

        $Result = New-Object -TypeName PSObject

        $RegKey = "HKLM\SYSTEM\CurrentControlSet\Control\BitLockerStatus"
        $RegValue = "BootStatus"
        $RegData = (Get-ItemProperty -Path "Registry::$($RegKey)" -Name $RegValue -ErrorAction SilentlyContinue).$RegValue
    
        $BitLockerEnabled = $false

        if ($null -eq $RegData) {
            $StatusDescription = "BitLocker is not configured."
        }
        else {
            if ($RegData -ge 1) {
                $BitLockerEnabled = $true
                $StatusDescription = "BitLocker is enabled."
            }
            else {
                $StatusDescription = "BitLocker is disabled."
            }
        }

        $Item = New-Object -TypeName PSObject
        $Item | Add-Member -MemberType "NoteProperty" -Name "Value" -Value $RegData
        $Item | Add-Member -MemberType "NoteProperty" -Name "Description" -Value $StatusDescription
        $Result | Add-Member -MemberType "NoteProperty" -Name "Status" -Value $Item

        $RegKey = "HKLM\SOFTWARE\Policies\Microsoft\FVE"

        $FveConfig.Clone().GetEnumerator() | ForEach-Object {
            $RegValue = $_.name
            $RegData = (Get-ItemProperty -Path "Registry::$($RegKey)" -Name $RegValue -ErrorAction SilentlyContinue).$RegValue
            if ($null -ne $RegData) {
                $FveConfig[$_.name] = $RegData
            }
        }

        if ($BitLockerEnabled) {
            foreach ($FveConfigItem in $FveConfig.GetEnumerator()) {

                $FveConfigValue = $FveConfigItem.name
                $FveConfigValueDescriptions = $FveConfigValues[$FveConfigValue]
                $IsValid = $true
    
                if (($FveConfigValue -eq "UseAdvancedStartup") -or ($FveConfigValue -eq "EnableBDEWithNoTPM")) {
                    if (($FveConfig[$FveConfigValue] -ne 0) -and ($FveConfig[$FveConfigValue] -ne 1)) {
                        $IsValid = $false
                    }
                }
                elseif (($FveConfigValue -eq "UseTPM") -or ($FveConfigValue -eq "UseTPMPIN") -or ($FveConfigValue -eq "UseTPMKey") -or ($FveConfigValue -eq "UseTPMKeyPIN")) {
                    if (($FveConfig[$FveConfigValue] -lt 0) -or ($FveConfig[$FveConfigValue] -gt 2)) {
                        $IsValid = $false
                    }
                }
    
                if (-not $IsValid) {
                    Write-Warning "Unexpected value for $($FveConfigValue): $($FveConfig[$FveConfigValue])"
                    continue
                }
    
                $Item = New-Object -TypeName PSObject
                $Item | Add-Member -MemberType "NoteProperty" -Name "Value" -Value $($FveConfig[$FveConfigValue])
                $Item | Add-Member -MemberType "NoteProperty" -Name "Description" -Value $($FveConfigValueDescriptions[$FveConfig[$FveConfigValue]])
    
                $Result | Add-Member -MemberType "NoteProperty" -Name $FveConfigValue -Value $Item
            }
        }

        $Result
    }
}

function Invoke-UacCheck {
    <#
    .SYNOPSIS
    Checks whether UAC (User Access Control) is enabled

    Author: @itm4n
    License: BSD 3-Clause

    .DESCRIPTION
    The state of UAC can be determined based on the value of the parameter "EnableLUA" in the following registry key:
    HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System
    0 = Disabled
    1 = Enabled

    .EXAMPLE
    PS C:\> Invoke-UacCheck | fl

    Key         : HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System
    Value       : EnableLUA
    Data        : 1
    Description : UAC is enabled
    Compliance  : True

    .NOTES
    "UAC was formerly known as Limited User Account (LUA)."
    IF EnableLUA = 0
        -> UAC is completely disabled, no other restriction can apply.
    ELSE
        -> UAC is enabled (default).
        IF LocalAccountTokenFilterPolicy = 1
            -> Every member of the local Administrators group is granted a high integrity token for remote connections.
        ELSE
            -> Only the default local Administrator account (with RID 500) is granted a high integrity token for remote connections (default).
            IF FilterAdministratorToken = 0
                -> The default local Administrator account (with RID 500) is granted a high integrity token for remote connections (default).
            ELSE
                -> The access token of the default local Administrator account (with RID 500) is filtered.

    .LINK
    https://docs.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-lua-settings-enablelua
    https://labs.f-secure.com/blog/enumerating-remote-access-policies-through-gpo/
    #>

    [CmdletBinding()] Param()

    $RegKey = "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System"
    $RegValue = "EnableLUA"
    $RegData = (Get-ItemProperty -Path "Registry::$($RegKey)" -Name $RegValue -ErrorAction SilentlyContinue).$RegValue
    $Description = $(if ($RegData -ge 1) { "UAC is enabled (default)" } else { "UAC is disabled" })
    Write-Verbose "$($RegValue): $($Description)"
    $Result = New-Object -TypeName PSObject
    $Result | Add-Member -MemberType "NoteProperty" -Name "Key" -Value $RegKey
    $Result | Add-Member -MemberType "NoteProperty" -Name "Value" -Value $RegValue
    $Result | Add-Member -MemberType "NoteProperty" -Name "Data" -Value $(if ($null -eq $RegData) { "(null)" } else { $RegData })
    $Result | Add-Member -MemberType "NoteProperty" -Name "Description" -Value $Description
    $Result | Add-Member -MemberType "NoteProperty" -Name "Compliance" -Value $($RegData -ge 1)
    $Result

    # If UAC is enabled, check LocalAccountTokenFilterPolicy to determine if only the built-in
    # administrator can get a high integrity token remotely or if any local user that is a
    # member of the Administrators group can also get one.
    if ($RegData -ge 1) {

        $RegKey = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        $RegValue = "LocalAccountTokenFilterPolicy"
        $RegData = (Get-ItemProperty -Path "Registry::$($RegKey)" -Name $RegValue -ErrorAction SilentlyContinue).$RegValue

        $Description = $(
            if ($RegData -ge 1) {
                "Local users that are members of the Administrators group are granted a high integrity token when authenticating remotely"
            }
            else {
                "Only the built-in Administrator account (RID 500) can be granted a high integrity token when authenticating remotely (default)"
            }
        )

        $Result = New-Object -TypeName PSObject
        $Result | Add-Member -MemberType "NoteProperty" -Name "Key" -Value $RegKey
        $Result | Add-Member -MemberType "NoteProperty" -Name "Value" -Value $RegValue
        $Result | Add-Member -MemberType "NoteProperty" -Name "Data" -Value $(if ($null -eq $RegData) { "(null)" } else { $RegData })
        $Result | Add-Member -MemberType "NoteProperty" -Name "Description" -Value $Description
        $Result | Add-Member -MemberType "NoteProperty" -Name "Compliance" -Value $($null -eq $RegData -or $RegData -eq 0)
        $Result

        # If LocalAccountTokenFilterPolicy != 1, i.e. local admins other than RID 500 are not granted a
        # high integrity token. However, we need to check if other restrictions apply to the built-in
        # administrator as well.
        if ($null -eq $RegData -or $RegData -eq 0) {

            $RegKey = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
            $RegValue = "FilterAdministratorToken"
            $RegData = (Get-ItemProperty -Path "Registry::$($RegKey)" -Name $RegValue -ErrorAction SilentlyContinue).$RegValue

            $Description = $(
                if ($RegData -ge 1) {
                    "The built-in Administrator account (RID 500) is only granted a medium integrity token when authenticating remotely."
                }
                else {
                    "The built-in administrator account (RID 500) is granted a high integrity token when authenticating remotely (default)."
                }
            )

            $Result = New-Object -TypeName PSObject
            $Result | Add-Member -MemberType "NoteProperty" -Name "Key" -Value $RegKey
            $Result | Add-Member -MemberType "NoteProperty" -Name "Value" -Value $RegValue
            $Result | Add-Member -MemberType "NoteProperty" -Name "Data" -Value $(if ($null -eq $RegData) { "(null)" } else { $RegData })
            $Result | Add-Member -MemberType "NoteProperty" -Name "Description" -Value $Description
            $Result | Add-Member -MemberType "NoteProperty" -Name "Compliance" -Value $($RegData -ge 1)
            $Result
        }
    }
}

function Invoke-LapsCheck {
    <#
    .SYNOPSIS
    Checks whether LAPS (Local Admin Password Solution) is enabled

    Author: @itm4n
    License: BSD 3-Clause

    .DESCRIPTION
    The status of LAPS can be check using the following registry key: HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft Services\AdmPwd

    .EXAMPLE
    PS C:\> Invoke-LapsCheck

    Key         : HKLM\SOFTWARE\Policies\Microsoft Services\AdmPwd
    Value       : AdmPwdEnabled
    Data        : (null)
    Description : LAPS is not configured
    Compliance  : False
    #>

    [CmdletBinding()] Param()

    $RegKey = "HKLM\SOFTWARE\Policies\Microsoft Services\AdmPwd"
    $RegValue = "AdmPwdEnabled"
    $RegData = (Get-ItemProperty -Path "Registry::$($RegKey)" -Name $RegValue -ErrorAction SilentlyContinue).$RegValue

    if ($null -eq $RegData) {
        $Description = "LAPS is not configured"
    }
    else {
        $Description = $(if ($RegData -ge 1) { "LAPS is enabled" } else { "LAPS is disabled" })
    }

    $Result = New-Object -TypeName PSObject
    $Result | Add-Member -MemberType "NoteProperty" -Name "Key" -Value $RegKey
    $Result | Add-Member -MemberType "NoteProperty" -Name "Value" -Value $RegValue
    $Result | Add-Member -MemberType "NoteProperty" -Name "Data" -Value $(if ($null -eq $RegData) { "(null)" } else { $RegData })
    $Result | Add-Member -MemberType "NoteProperty" -Name "Description" -Value $Description
    $Result | Add-Member -MemberType "NoteProperty" -Name "Compliance" -Value $($RegData -ge 1)
    $Result
}

function Invoke-PowershellTranscriptionCheck {
    <#
    .SYNOPSIS
    Checks whether PowerShell Transcription is configured/enabled

    Author: @itm4n
    License: BSD 3-Clause

    .DESCRIPTION
    Powershell Transcription is used to log PowerShell scripts execution. It can be configured thanks to the Group Policy Editor. The settings are stored in the following registry key: HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription

    .EXAMPLE
    PS C:\> Invoke-PowershellTranscriptionCheck | fl

    EnableTranscripting    : 1
    EnableInvocationHeader : 1
    OutputDirectory        : C:\Transcripts

    .NOTES
    If PowerShell Transcription is configured, the settings can be found here:

    C:\>reg query HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription

    HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription
        EnableTranscripting    REG_DWORD    0x1
        OutputDirectory    REG_SZ    C:\Transcripts
        EnableInvocationHeader    REG_DWORD    0x1

    To enable PowerShell Transcription:
    Group Policy Editor > Administrative Templates > Windows Components > Windows PowerShell > PowerShell Transcription
    Set an output directory and set the policy as Enabled
    #>

    [CmdletBinding()] Param()

    $RegKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription"
    $RegItem = Get-ItemProperty -Path "Registry::$($RegKey)" -ErrorAction SilentlyContinue

    if ($RegItem) {
        $Result = New-Object -TypeName PSObject
        $Result | Add-Member -MemberType "NoteProperty" -Name "EnableTranscripting" -Value $(if ($null -eq $RegItem.EnableTranscripting) { "(null)" } else { $RegItem.EnableTranscripting })
        $Result | Add-Member -MemberType "NoteProperty" -Name "EnableInvocationHeader" -Value $(if ($null -eq $RegItem.EnableInvocationHeader) { "(null)" } else { $RegItem.EnableInvocationHeader })
        $Result | Add-Member -MemberType "NoteProperty" -Name "OutputDirectory" -Value $(if ($null -eq $RegItem.OutputDirectory) { "(null)" } else { $RegItem.OutputDirectory })
        $Result
    }
}

function Invoke-BitLockerCheck {
    <#
    .SYNOPSIS
    Checks whether BitLocker is enabled.

    Author: @itm4n
    License: BSD 3-Clause

    .DESCRIPTION
    When BitLocker is enabled on the system drive, the value "BootStatus" is set to 1 in the following registry key: 'HKLM\SYSTEM\CurrentControlSet\Control\BitLockerStatus'.

    .EXAMPLE
    PS C:\> Invoke-BitlockerCheck

    MachineRole        : Workstation
    UseAdvancedStartup : 0 - Do not require additional authentication at startup (default)
    EnableBDEWithNoTPM : 0 - Do not allow BitLocker without a compatible TPM (default)
    UseTPM             : 1 - Require TPM (default)
    UseTPMPIN          : 0 - Do not allow startup PIN with TPM (default)
    UseTPMKey          : 0 - Do not allow startup key with TPM (default)
    UseTPMKeyPIN       : 0 - Do not allow startup key and PIN with TPM (default)
    Description        : BitLocker is enabled. Additional authentication is not required on startup. Authentication mode is 'TPM only'.
    Compliance         : False
    #>

    [CmdletBinding()] Param()

    $MachineRole = Get-MachineRole
    $Compliance = $false

    $Result = New-Object -TypeName PSObject
    $Result | Add-Member -MemberType "NoteProperty" -Name "MachineRole" -Value $MachineRole.Role

    if ($MachineRole.Name -eq "WinNT") {
        $Config = Get-BitLockerConfiguration

        # $Result | Add-Member -MemberType "NoteProperty" -Name "Status" -Value "$(if ($null -eq $Config.Status.Value) { "(null)" } else { $Config.Status.Value }) - $($Config.Status.Description)"
        $Description = "$($Config.Status.Description) "

        if ($Config.Status.Value -eq 1) {
            $Result | Add-Member -MemberType "NoteProperty" -Name "UseAdvancedStartup" -Value "$($Config.UseAdvancedStartup.Value) - $($Config.UseAdvancedStartup.Description)"
            $Result | Add-Member -MemberType "NoteProperty" -Name "EnableBDEWithNoTPM" -Value "$($Config.EnableBDEWithNoTPM.Value) - $($Config.EnableBDEWithNoTPM.Description)"
            $Result | Add-Member -MemberType "NoteProperty" -Name "UseTPM" -Value "$($Config.UseTPM.Value) - $($Config.UseTPM.Description)"
            $Result | Add-Member -MemberType "NoteProperty" -Name "UseTPMPIN" -Value "$($Config.UseTPMPIN.Value) - $($Config.UseTPMPIN.Description)"
            $Result | Add-Member -MemberType "NoteProperty" -Name "UseTPMKey" -Value "$($Config.UseTPMKey.Value) - $($Config.UseTPMKey.Description)"
            $Result | Add-Member -MemberType "NoteProperty" -Name "UseTPMKeyPIN" -Value "$($Config.UseTPMKeyPIN.Value) - $($Config.UseTPMKeyPIN.Description)"

            if ($Config.UseAdvancedStartup.Value -eq 1) {
                if (($Config.UseTPMPIN.Value -eq 1) -or ($Config.UseTPMKey.Value -eq 1) -or ($Config.UseTPMKeyPIN -eq 1)) {
                    $Compliance = $true
                    if ($Config.UseTPMPIN.Value -eq 1) {
                        $Description = "$($Description)A PIN is required. "
                    }
                    if ($Config.UseTPMKey.Value -eq 1) {
                        $Description = "$($Description)A startup key is required. "
                    }
                    if ($Config.UseTPMKeyPIN -eq 1) {
                        $Description = "$($Description)A PIN and a startup key are required. "
                    }
                }
                else {
                    $Description = "$($Description)A second factor of authentication (PIN, startup key) is not explicitely required. "
                    if ($Config.EnableBDEWithNoTPM.Value -eq 1) {
                        $Description = "$($Description)BitLocker without a compatible TPM is allowed. "
                    }
                }
            }
            else {
                $Description = "$($Description)Additional authentication is not required on startup. "
                if ($Config.UseTPM.Value -eq 1) {
                    $Description = "$($Description)Authentication mode is 'TPM only'. "
                }
            }
        }
    }
    else {
        # This is not a workstation, the BitLocker configuration is not relevant.
        $Compliance = $true
        $Description = "Not a workstation, BitLocker configuration is irrelevant."
    }

    $Result | Add-Member -MemberType "NoteProperty" -Name "Description" -Value $Description
    $Result | Add-Member -MemberType "NoteProperty" -Name "Compliance" -Value $Compliance
    $Result
}

function Invoke-LsaProtectionCheck {
    <#
    .SYNOPSIS
    Checks whether LSA protection is supported and enabled

    Author: @itm4n
    License: BSD 3-Clause

    .DESCRIPTION
    Invokes the helper function Get-LsaRunAsPPLStatus

    .EXAMPLE
    PS C:\> Invoke-LsaProtectionCheck

    Path        : HKLM\SYSTEM\CurrentControlSet\Control\Lsa
    Value       : RunAsPPL
    Data        : (null)
    Description : RunAsPPL is either not configured or disabled
    Compliance  : False
    #>

    [CmdletBinding()] Param()

    $OsVersion = Get-WindowsVersion

    $RegKey = "HKLM\SYSTEM\CurrentControlSet\Control\Lsa"
    $RegValue = "RunAsPPL"
    $RegData = (Get-ItemProperty -Path "Registry::$($RegKey)" -Name $RegValue -ErrorAction SilentlyContinue).$RegValue

    $Description = $(if ($RegData -ge 1) { "RunAsPPL is enabled" } else { "RunAsPPL is not enabled" })

    # If < Windows 8.1 / 2012 R2
    if (-not ($OsVersion.Major -ge 10 -or (($OsVersion.Major -eq 6) -and ($OsVersion.Minor -ge 3)))) {
        $Description = "RunAsPPL is not supported on this OS"
    }

    $Result = New-Object -TypeName PSObject
    $Result | Add-Member -MemberType "NoteProperty" -Name "Key" -Value $RegKey
    $Result | Add-Member -MemberType "NoteProperty" -Name "Value" -Value $RegValue
    $Result | Add-Member -MemberType "NoteProperty" -Name "Data" -Value $(if ($null -eq $RegData) { "(null)" } else { $RegData })
    $Result | Add-Member -MemberType "NoteProperty" -Name "Description" -Value $Description
    $Result | Add-Member -MemberType "NoteProperty" -Name "Compliance" -Value $($RegData -ge 1)
    $Result
}

function Invoke-CredentialGuardCheck {
    <#
    .SYNOPSIS
    Checks whether Credential Guard is supported and enabled

    Author: @itm4n
    License: BSD 3-Clause

    .DESCRIPTION
    Invokes the helper function Get-CredentialGuardStatus

    .EXAMPLE
    PS C:\> Invoke-CredentialGuardCheck

    Name                                  : Credential Guard
    DeviceGuardSecurityServicesConfigured : (null)
    DeviceGuardSecurityServicesRunning    : (null)
    Description                           : Credential Guard is not configured
    Compliance                            : False
    #>

    [CmdletBinding()] Param()

    $OsVersion = Get-WindowsVersion

    if ($OsVersion.Major -ge 10) {

        if ((($PSVersionTable.PSVersion.Major -eq 5) -and ($PSVersionTable.PSVersion.Minor -ge 1)) -or ($PSVersionTable.PSVersion.Major -gt 5)) {

            $DeviceGuardSecurityServicesConfigured = (Get-ComputerInfo).DeviceGuardSecurityServicesConfigured
            if ($DeviceGuardSecurityServicesConfigured -match 'CredentialGuard') {

                $Compliance = $false
                $Description = "Credential Guard is configured but is not running"

                $DeviceGuardSecurityServicesRunning = (Get-ComputerInfo).DeviceGuardSecurityServicesRunning
                if ($DeviceGuardSecurityServicesRunning -match 'CredentialGuard') {
                    $Compliance = $true
                    $Description = "Credential Guard is configured and running"
                }
            }
            else {
                $Compliance = $false
                $Description = "Credential Guard is not configured"
            }
        }
        else {
            $Compliance = $false
            $Description = "Check failed: Incompatible PS version"
        }
    }
    else {
        $Compliance = $false
        $Description = "Credential Guard is not supported on this OS"
    }

    $Result = New-Object -TypeName PSObject
    $Result | Add-Member -MemberType "NoteProperty" -Name "Name" -Value "Credential Guard"
    $Result | Add-Member -MemberType "NoteProperty" -Name "DeviceGuardSecurityServicesConfigured" -Value $(if ($null -eq $DeviceGuardSecurityServicesConfigured) { "(null)" } else { $DeviceGuardSecurityServicesConfigured })
    $Result | Add-Member -MemberType "NoteProperty" -Name "DeviceGuardSecurityServicesRunning" -Value $(if ($null -eq $DeviceGuardSecurityServicesRunning) { "(null)" } else { $DeviceGuardSecurityServicesConfigured })
    $Result | Add-Member -MemberType "NoteProperty" -Name "Description" -Value $Description
    $Result | Add-Member -MemberType "NoteProperty" -Name "Compliance" -Value $Compliance
    $Result
}

function Invoke-BiosModeCheck {
    <#
    .SYNOPSIS
    Checks whether UEFI and Secure are supported and enabled

    Author: @itm4n
    License: BSD 3-Clause

    .DESCRIPTION
    Invokes the helper functions Get-UEFIStatus and Get-SecureBootStatus

    .EXAMPLE
    PS C:\> Invoke-BiosModeCheck

    Name        Status Description
    ----        ------ -----------
    UEFI          True BIOS mode is UEFI
    Secure Boot  False Secure Boot is disabled
    #>

    Get-UEFIStatus

    $SecureBoot = Get-SecureBootStatus
    $Result = New-Object -TypeName PSObject
    $Result | Add-Member -MemberType "NoteProperty" -Name "Name" -Value "Secure Boot"
    $Result | Add-Member -MemberType "NoteProperty" -Name "Status" -Value $SecureBoot.Compliance
    $Result | Add-Member -MemberType "NoteProperty" -Name "Description" -Value $SecureBoot.Description
    $Result
}