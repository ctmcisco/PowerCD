function Invoke-PowerCDClean {
    [CmdletBinding()]
    param (
        $buildProjectPath = $PCDSetting.BuildEnvironment.ProjectPath,
        $buildOutputPath  = $PCDSetting.BuildEnvironment.BuildOutput,
        $buildProjectName = $PCDSetting.BuildEnvironment.ProjectName
    )

    #Taken from Invoke-Build because it does not preserve the command in the scope this function normally runs
    #Copyright (c) Roman Kuzmin
    function Remove-BuildItem([Parameter(Mandatory=1)][string[]]$Path) {
        if ($Path -match '^[.*/\\]*$') {*Die 'Not allowed paths.' 5}
        $v = $PSBoundParameters['Verbose']
        try {
            foreach($_ in $Path) {
                if (Get-Item $_ -Force -ErrorAction 0) {
                    if ($v) {Write-Verbose "remove: removing $_" -Verbose}
                    Remove-Item $_ -Force -Recurse -ErrorAction stop
                }
                elseif ($v) {Write-Verbose "remove: skipping $_" -Verbose}
            }
        }
        catch {
            throw $_
        }
    }

    #Reset the BuildOutput Directory
    if (test-path $buildProjectPath) {
        Write-Verbose "Removing and resetting Build Output Path: $buildProjectPath"
        Remove-BuildItem $buildOutputPath 4>$null
    }

    New-Item -Type Directory $BuildOutputPath > $null

    #Unmount any modules named the same as our module
    Remove-Module $buildProjectName -erroraction silentlycontinue
}

