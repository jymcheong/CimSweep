﻿function Get-CSVulnerableServicePermission {
<#
.SYNOPSIS

Lists each group granted potentially vulnerable service access permissions.

Author: Matthew Graeber (@mattifestation)
License: BSD 3-Clause

.DESCRIPTION

Get-CSVulnerableServicePermission is used to perform service ACL audits at scale. For each computer, it iterates through the service and associated file permissions and groups potentially vulnerable access rights granted to each user. This can be used to quickly identify if members of lower privileged groups can elevate privileges via service misconfigurations.

.PARAMETER IncludeDrivers

Specifies that driver file permissions should be queried in addition to user-mode services. Read the notes section for more information about the limitations of driver audits.

.PARAMETER CimSession

Specifies the CIM session to use for this cmdlet. Enter a variable that contains the CIM session or a command that creates or gets the CIM session, such as the New-CimSession or Get-CimSession cmdlets. For more information, see about_CimSessions.

.EXAMPLE

Get-CSVulnerableServicePermission

Returns a list of groups and the services to which they are granted access to perform potentially vulnerable actions.

.OUTPUTS

CimSweep.ServiceACLAudit

Outputs objects representing each group granted potentially vulnerable service and file access rights.

.NOTES

Driver services (Win32_SystemDriver) do not expose the GetSecurityDescriptor method so service ACLs cannot be obtained. File permissions can be obtained, however. Just be mindful of this if you notice that driver services appear to not be granted any service access rights.

Service ACL sweep across a large amount of hosts will take a long time.
#>

    [CmdletBinding()]
    [OutputType('CimSweep.ServiceACLAudit')]
    param (
        [Switch]
        $IncludeDrivers,

        [Alias('Session')]
        [ValidateNotNullOrEmpty()]
        [Microsoft.Management.Infrastructure.CimSession[]]
        $CimSession
    )

    BEGIN {
        if (-not $PSBoundParameters['CimSession']) {
            $CimSession = ''
            $CIMSessionCount = 1
        } else {
            $CIMSessionCount = $CimSession.Count
        }

        $CurrentCIMSession = 0

        $UserModeServices = @{}
        if (-not $IncludeDrivers) {
            $UserModeServices['UserModeServices'] = $True
        }
    }

    PROCESS {
        foreach ($Session in $CimSession) {
            $ComputerName = $Session.ComputerName
            if (-not $Session.ComputerName) { $ComputerName = 'localhost' }

            # Display a progress activity for each CIM session
            Write-Progress -Id 1 -Activity 'CimSweep - Service ACL sweep' -Status "($($CurrentCIMSession+1)/$($CIMSessionCount)) Current computer: $ComputerName" -PercentComplete (($CurrentCIMSession / $CIMSessionCount) * 100)
            $CurrentCIMSession++

            $CommonArgs = @{}

            if ($Session.Id) { $CommonArgs['CimSession'] = $Session }

            $UserGrouping = @{}

            Get-CSService -IncludeAcl -IncludeFileInfo @UserModeServices @CommonArgs | ForEach-Object {
                $ServiceName = $_.Name

                Write-Progress -Id 2 -ParentId 1 -Activity "   Current service:" -Status $ServiceName

                foreach ($FileDACL in $_.FileInfo.ACL.Access) {
                        $GroupName = $FileDACL.IdentityReference.ToString()

                        if (-not $UserGrouping.ContainsKey($GroupName)) {
                            $Permissions = [PSCustomObject] @{
                                ServiceCanStart = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                                ServiceCanStop = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                                ServiceCanChangeConfig = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                                ServiceHasAllAccess = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                                FileCanChangePermissions = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                                FileCanDelete = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                                FileCanModify = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                                FileCanTakeOwnership = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                                FileCanWrite = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                                FileCanWriteData = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                                FileHasFullControl = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                            }
                        } else {
                            $Permissions = $UserGrouping[$GroupName]
                        }

                        $UserGrouping[$GroupName] = $Permissions
        
                        if (($FileDACL.AccessControlType -eq 'Allow') -and $FileDACL.FileSystemRights.HasFlag([Security.AccessControl.FileSystemRights]::ChangePermissions)) {
                            $UserGrouping[$GroupName].FileCanChangePermissions.Add($ServiceName)
                        }

                        if (($FileDACL.AccessControlType -eq 'Allow') -and $FileDACL.FileSystemRights.HasFlag([Security.AccessControl.FileSystemRights]::Delete)) {
                            $UserGrouping[$GroupName].FileCanDelete.Add($ServiceName)
                        }

                        if (($FileDACL.AccessControlType -eq 'Allow') -and $FileDACL.FileSystemRights.HasFlag([Security.AccessControl.FileSystemRights]::Modify)) {
                            $UserGrouping[$GroupName].FileCanModify.Add($ServiceName)
                        }

                        if (($FileDACL.AccessControlType -eq 'Allow') -and $FileDACL.FileSystemRights.HasFlag([Security.AccessControl.FileSystemRights]::TakeOwnership)) {
                            $UserGrouping[$GroupName].FileCanTakeOwnership.Add($ServiceName)
                        }

                        if (($FileDACL.AccessControlType -eq 'Allow') -and $FileDACL.FileSystemRights.HasFlag([Security.AccessControl.FileSystemRights]::Write)) {
                            $UserGrouping[$GroupName].FileCanWrite.Add($ServiceName)
                        }

                        if (($FileDACL.AccessControlType -eq 'Allow') -and $FileDACL.FileSystemRights.HasFlag([Security.AccessControl.FileSystemRights]::WriteData)) {
                            $UserGrouping[$GroupName].FileCanWriteData.Add($ServiceName)
                        }

                        if (($FileDACL.AccessControlType -eq 'Allow') -and $FileDACL.FileSystemRights.HasFlag([Security.AccessControl.FileSystemRights]::FullControl)) {
                            $UserGrouping[$GroupName].FileHasFullControl.Add($ServiceName)
                        }
                }

                foreach ($DACL in $_.ACL.Access) {
                    $RightsType = $DACL.Rights.GetType()

                    $GroupName = $DACL.IdentityReference.ToString()

                    if (-not $UserGrouping.ContainsKey($GroupName)) {
                        $Permissions = [PSCustomObject] @{
                            ServiceCanStart = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                            ServiceCanStop = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                            ServiceCanChangeConfig = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                            ServiceHasAllAccess = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                            FileCanChangePermissions = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                            FileCanDelete = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                            FileCanModify = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                            FileCanTakeOwnership = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                            FileCanWrite = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                            FileCanWriteData = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                            FileHasFullControl = (New-Object 'Collections.ObjectModel.Collection`1[System.String]')
                        }
                    } else {
                        $Permissions = $UserGrouping[$GroupName]
                    }

                    $UserGrouping[$GroupName] = $Permissions
        
                    if (($DACL.AccessControlType -eq 'Allow') -and $DACL.Rights.HasFlag($RightsType::Start)) {
                        $UserGrouping[$GroupName].ServiceCanStart.Add($ServiceName)
                    }

                    if (($DACL.AccessControlType -eq 'Allow') -and $DACL.Rights.HasFlag($RightsType::Stop)) {
                        $UserGrouping[$GroupName].ServiceCanStop.Add($ServiceName)
                    }

                    if (($DACL.AccessControlType -eq 'Allow') -and $DACL.Rights.HasFlag($RightsType::ChangeConfig)) {
                        $UserGrouping[$GroupName].ServiceCanChangeConfig.Add($ServiceName)
                    }

                    if (($DACL.AccessControlType -eq 'Allow') -and $DACL.Rights.HasFlag($RightsType::AllAccess)) {
                        $UserGrouping[$GroupName].ServiceHasAllAccess.Add($ServiceName)
                    }
                }
            }

            foreach ($Group in $UserGrouping.Keys) {
                $Permissions = $UserGrouping[$Group]

                $ObjectProperties = [Ordered] @{
                    PSTypeName = 'CimSweep.ServiceACLAudit'
                    GroupName = $Group
                    CanStartService = $Permissions.ServiceCanStart
                    CanStopService = $Permissions.ServiceCanStop
                    CanChangeServiceConfig = $Permissions.ServiceCanChangeConfig
                    AllAccessToService = $Permissions.ServiceHasAllAccess
                    CanChangePermissionsOfFile = $Permissions.FileCanChangePermissions
                    CanDeleteFile = $Permissions.FileCanDelete
                    CanModifyFile = $Permissions.FileCanModify
                    CanTakeOwnershipOfFile = $Permissions.FileCanTakeOwnership
                    CanWriteToFile = $Permissions.FileCanWrite
                    CanWriteDataToFile = $Permissions.FileCanWriteData
                    FullControlOfFile = $Permissions.FileHasFullControl
                }

                if ($Session.ComputerName) { $ObjectProperties['PSComputerName'] = $Session.ComputerName }

                [PSCustomObject] $ObjectProperties
            }
        }
    }
}

Export-ModuleMember -Function Get-CSVulnerableServicePermission