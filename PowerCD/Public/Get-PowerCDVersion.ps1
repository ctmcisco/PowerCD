using namespace System.IO
function Get-PowerCDVersion {
    [CmdletBinding()]
    param()

    #TODO: Potentially pin the GitVersion version, as pulling from multiple sources may have undesirable side effect of different version for different builds
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        & dotnet tool install -g gitversion.tool *>&1 | write-verbose
        $GitversionExe = "$HOME/.dotnet/tools/dotnet-gitversion"
        Write-Debug "GitVersion: Dotnet EXE detected, using .NET Global Tool"
    } elseif ($IsWindows -or $PSEdition -eq 'Desktop') {
        Write-Debug "Gitversion: Dotnet not found but we are on Windows, using GitVersion.CommandLine package (faster than downloading dotnet)"
        $GitVersionPackagePath = Import-PowerCDRequirement GitVersion.CommandLine -Package
        $GitVersionEXE = [IO.Path]::Combine($GitVersionPackagePath,'tools','GitVersion.exe')
    } elseif ($MacOS) {
        Write-Debug "Gitversion: Dotnet not found but we are on Mac, using gitversion package on brew (faster than downloading dotnet)"
        & brew install GitVersion
        $GitversionEXE = 'gitversion'
    } else {
        throw "The version task requires the dotnet SDK to be installed if not running on Windows or Mac. For ubuntu you can install with apt-get install dotnet-sdk-3.0"
    }

    #If this commit has a tag on it, temporarily remove it so GitVersion calculates properly
    #Fixes a bug with GitVersion where tagged commits don't increment on non-master builds.
    $currentTag = git tag --points-at HEAD

    if ($currentTag) {
        write-verbose "Task $($task.name) - Git Tag $currentTag detected. Temporarily removing for GitVersion calculation."
        git tag -d $currentTag
    }

    #Strip prerelease tags, GitVersion can't handle them with Mainline deployment with version 4.0
    #TODO: Restore these for local repositories, otherwise they just come down with git pulls
    #FIXME: Remove this because
    #git tag --list v*-* | % {git tag -d $PSItem}

    try {
        #Calculate the GitVersion
        write-verbose "Executing GitVersion to determine version info"

        if ($isLinux -and -not $isAppveyor) {
            #TODO: Find a more platform-independent way of changing GitVersion executable permissions (Mono.Posix library maybe?)
            #https://www.nuget.org/packages/Mono.Posix.NETStandard/1.0.0
            chmod +x $GitVersionEXE
        }

        $GitVersionOutput = & $GitVersionEXE /nofetch
        if (-not $GitVersionOutput) {throw "GitVersion returned no output. Are you sure it ran successfully?"}

        #Since GitVersion doesn't return error exit codes, we look for error text in the output
        if ($GitVersionOutput -match '^[ERROR|INFO] \[') {throw "An error occured when running GitVersion.exe in $buildRoot"}
        $SCRIPT:GitVersionInfo = $GitVersionOutput | ConvertFrom-JSON -ErrorAction stop

        if ($PCDSetting.Debug) {
            & $gitversionexe /nofetch /diag | write-debug
        }

        $GitVersionInfo | format-list | out-string | write-verbose

        [Version]$PCDSetting.Version     = $GitVersionInfo.MajorMinorPatch

        #TODO: Older packagemanagement don't support hyphens in Nuget name for some reason. Restore when fixed
        #[String]$PCDSetting.PreRelease   = $GitVersionInfo.NuGetPreReleaseTagV2
        #[String]$PCDSetting.VersionLabel = $GitVersionInfo.NuGetVersionV2
        #Remove separator characters for now, for instance in branch names
        [String]$PCDSetting.PreRelease   = $GitVersionInfo.NuGetPreReleaseTagV2 -replace '[\/\\\-]',''
        [String]$PCDSetting.VersionLabel = $PCDSetting.Version,$PCDSetting.PreRelease -join '-'

        if ($PCDSetting.BuildEnvironment.BuildOutput) {
            $PCDSetting.BuildModuleOutput = [io.path]::Combine($PCDSetting.BuildEnvironment.BuildOutput,$PCDSetting.BuildEnvironment.ProjectName,$PCDSetting.Version)
        }
    } catch {
        write-warning "There was an error when running GitVersion.exe $buildRoot`: $PSItem. The output of the command (if any) is below...`r`n$GitVersionOutput"
        & $GitVersionexe
    } finally {
        #Restore the tag if it was present
        #TODO: Evaluate if this is still necessary
        # if ($currentTag) {
        #     write-build DarkYellow "Task $($task.name) - Restoring tag $currentTag."
        #     git tag $currentTag -a -m "Automatic GitVersion Release Tag Generated by Invoke-Build"
        # }
    }

    return $GitVersionOutput

    # #GA release detection
    # if ($BranchName -eq 'master') {
    #     $Script:IsGARelease = $true
    #     $Script:ProjectVersion = $ProjectBuildVersion
    # } else {
    #     #The regex strips all hypens but the first one. This shouldn't be necessary per NuGet spec but Update-ModuleManifest fails on it.
    #     $SCRIPT:ProjectPreReleaseVersion = $GitVersionInfo.nugetversion -replace '(?<=-.*)[-]'
    #     $SCRIPT:ProjectVersion = $ProjectPreReleaseVersion
    #     $SCRIPT:ProjectPreReleaseTag = $SCRIPT:ProjectPreReleaseVersion.split('-')[1]
    # }

    # write-build Green "Task $($task.name)` - Calculated Project Version: $ProjectVersion"

    # #Tag the release if this is a GA build
    # if ($BranchName -match '^(master|releases?[/-])') {
    #     write-build Green "Task $($task.name)` - In Master/Release branch, adding release tag v$ProjectVersion to this build"

    #     $SCRIPT:isTagRelease = $true
    #     if ($BranchName -eq 'master') {
    #         write-build Green "Task $($task.name)` - In Master branch, marking for General Availability publish"
    #         [Switch]$SCRIPT:IsGARelease = $true
    #     }
    # }

    # #Reset the build dir to the versioned release directory. TODO: This should probably be its own task.
    # $SCRIPT:BuildReleasePath = Join-Path $BuildProjectPath $ProjectBuildVersion
    # if (-not (Test-Path -pathtype Container $BuildReleasePath)) {New-Item -type Directory $BuildReleasePath | out-null}
    # $SCRIPT:BuildReleaseManifest = Join-Path $BuildReleasePath (split-path $env:BHPSModuleManifest -leaf)
    # write-build Green "Task $($task.name)` - Using Release Path: $BuildReleasePath"
}