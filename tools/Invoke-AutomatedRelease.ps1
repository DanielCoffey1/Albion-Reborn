param([Parameter(Mandatory)][string]$ConfigPath,[switch]$ValidateOnly,[switch]$Force)
$ErrorActionPreference='Stop'
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$root=[IO.Path]::GetFullPath($config.root)
[IO.Directory]::CreateDirectory($root) | Out-Null
$lock=[IO.File]::Open((Join-Path $root 'publish.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
function Checked([string]$Program,[string[]]$Arguments){& $Program @Arguments | ForEach-Object {Write-Host $_};if($LASTEXITCODE){throw "$Program failed with exit $LASTEXITCODE"}}
function Sync-Repository([string]$Name){
    $path=Join-Path $root ('repos\'+$Name)
    if(!(Test-Path (Join-Path $path '.git'))){Checked 'gh' @('repo','clone',('DanielCoffey1/'+$Name),$path,'--','--branch','main')}
    # ReXGlue rewrites these tracked metadata files with LF endings. Git may
    # report them modified even when its normalized diff is empty. Restore only
    # this known generated metadata, and only after confirming no text change.
    $metadata=@('generated/rexglue.cmake',$(if($Name -eq 'Fable-II-PC'){'fable_2_manifest.toml'}else{'fable_3_manifest.toml'}))
    foreach($relative in $metadata){
        $reported=@(& git -C $path status --porcelain -- $relative)
        if($reported.Count){
            & git -C $path diff --quiet HEAD -- $relative
            if($LASTEXITCODE -eq 0){Checked 'git' @('-C',$path,'restore','--worktree','--source=HEAD','--',$relative)}
        }
    }
    if(@(& git -C $path status --porcelain --untracked-files=no --ignore-submodules=dirty).Count){throw "Agent checkout has tracked changes: $Name. Original development checkouts were not touched."}
    Checked 'git' @('-C',$path,'fetch','origin','main')
    Checked 'git' @('-C',$path,'merge','--ff-only','origin/main')
    return $path
}
try {
    $launcher=Join-Path $root 'repos\Albion-Reborn'
    . (Join-Path $launcher 'Update.Core.ps1')
    $f2=Sync-Repository 'Fable-II-PC';$f3=Sync-Repository 'Fable-III-PC'
    $heads=@{launcher=(& git -C $launcher rev-parse HEAD).Trim();fable2=(& git -C $f2 rev-parse HEAD).Trim();fable3=(& git -C $f3 rev-parse HEAD).Trim()}
    $signature=$heads.launcher+':'+$heads.fable2+':'+$heads.fable3
    $statePath=Join-Path $root 'published.json'
    if(!$Force -and (Test-Path $statePath) -and (Get-Content $statePath -Raw | ConvertFrom-Json).signature -eq $signature){Write-Output 'No unpublished source changes.';return}
    $specs=Get-Content (Join-Path $launcher 'packaging\runtime-specs.json') -Raw | ConvertFrom-Json
    foreach($item in $specs.runtimes){
        $gameRoot=if($item.id -eq 'fable2'){$config.fable2Content}else{$config.fable3Content}
        if((Get-FileHash (Join-Path $gameRoot 'default.xex') -Algorithm SHA256).Hash -ne $item.xexSha256){throw "Missing or unsupported local content for $($item.id)"}
        $item.version='source-'+$heads[$item.id].Substring(0,12)
        $item | Add-Member sourceCommit $heads[$item.id]
    }
    $vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vs=(& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
    if(!$vs){throw 'Visual Studio C++ build tools not found.'}
    $devcmd=Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
    $environment=& $env:ComSpec /d /c "call `"$devcmd`" -no_logo -arch=x64 -host_arch=x64 >nul && set"
    if($LASTEXITCODE){throw 'Failed to initialize the build environment.'}
    foreach($line in $environment){if($line -match '^([^=]+)=(.*)$'){[Environment]::SetEnvironmentVariable($Matches[1],$Matches[2],'Process')}}
    $cmakeBin=Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin'
    $ninjaBin=Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja'
    $llvm=if($config.llvmBin){$config.llvmBin}else{Join-Path $vs 'VC\Tools\Llvm\x64\bin'}
    $env:PATH="$llvm;$cmakeBin;$ninjaBin;$($config.pythonDirectory);$env:PATH"
    $env:CMAKE_BUILD_PARALLEL_LEVEL=[string]$config.jobs
    $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    # Only these build checkouts receive links to local inputs. They are never
    # workflow artifacts or release assets.
    if(!(Test-Path (Join-Path $f2 'default.xex'))){Copy-Item -LiteralPath (Join-Path $config.fable2Content 'default.xex') -Destination (Join-Path $f2 'default.xex')}
    if(!(Test-Path (Join-Path $f3 'game'))){New-Item -ItemType Junction -Path (Join-Path $f3 'game') -Target $config.fable3Content | Out-Null}
    Checked $ps @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $f3 'tools\setup-sdk.ps1'))
    $sdk=Join-Path $f3 'tooling\rexglue-sdk'
    $official=Join-Path $f2 'out\tooling\rexglue-sdk-0.10.0\win-amd64'
    if(!(Test-Path $official)){[IO.Directory]::CreateDirectory((Split-Path $official -Parent)) | Out-Null;New-Item -ItemType Junction -Path $official -Target $sdk | Out-Null}
    Push-Location $f2
    try{
        if(!(Test-Path (Join-Path $f2 'generated\default\sources.cmake'))){Checked (Join-Path $sdk 'bin\rexglue.exe') @('codegen','fable_2_manifest.toml')}
        Checked $env:ComSpec @('/d','/c','build.cmd -release fable_2')
        Checked 'python' @('-m','unittest','discover','-s','tests','-p','test_*.py')
        Checked $env:ComSpec @('/d','/c','tests\run_native_tests.cmd')
    }finally{Pop-Location}
    Push-Location $f3
    try{
        if(!(Test-Path (Join-Path $f3 'generated\default\sources.cmake'))){Checked (Join-Path $sdk 'bin\rexglue.exe') @('codegen','fable_3_manifest.toml')}
        Checked $ps @('-NoProfile','-ExecutionPolicy','Bypass','-File','tools\build.ps1','-Jobs',([string]$config.jobs))
        if(Test-Path 'tools\test-display.ps1'){Checked $ps @('-NoProfile','-ExecutionPolicy','Bypass','-File','tools\test-display.ps1')}
    }finally{Pop-Location}
    $runtime2=Join-Path $f2 'out\build\win-amd64-release';$runtime3=Join-Path $f3 'out\build\win-amd64-release'
    foreach($entry in @(@{root=$runtime2;exe='fable_2.exe'},@{root=$runtime3;exe='fable_3.exe'})){
        $imports=& (Join-Path $llvm 'llvm-readobj.exe') --coff-imports (Join-Path $entry.root $entry.exe)
        if($LASTEXITCODE -ne 0 -or !($imports -match '^\s*Name: rexruntime.dll\s*$')){throw "Invalid native runtime import: $($entry.exe)"}
        if(!(Test-Path (Join-Path $entry.root 'rexruntime.dll'))){throw 'Linked runtime DLL was not staged.'}
    }
    foreach($seed in @('fable_2.toml','fable2_config.toml')){Copy-Item -LiteralPath (Join-Path $f2 ('profiles\smooth-60\'+$seed)) -Destination (Join-Path $runtime2 $seed)}
    $prefix=[version]'0.3.2'
    $latest=Get-AlbionOnlineUpdate
    if($latest){$publishedPrefix=[version]$latest.version.Split('-')[0];if($publishedPrefix -gt $prefix){$prefix=$publishedPrefix}}
    $buildId=$prefix.ToString()+'-preview-'+[datetime]::UtcNow.ToString('yyyyMMddHHmmss');$tag='v'+$buildId
    if($latest -and (Compare-AlbionBuild $buildId $latest.version) -le 0){throw 'Build clock/version is not newer than the published release.'}
    $releaseRoot=Join-Path $root ('releases\'+$buildId);[IO.Directory]::CreateDirectory($releaseRoot) | Out-Null
    $specPath=Join-Path $releaseRoot 'runtime-specs.json';$specs | ConvertTo-Json -Depth 8 | Set-Content $specPath -Encoding UTF8
    $crt=Get-ChildItem (Join-Path $vs 'VC\Redist\MSVC') -Directory | Where-Object {$_.Name -match '^14\.'} | Sort-Object Name -Descending | Select-Object -First 1
    $packages=Join-Path $releaseRoot 'packages';$distribution=Join-Path $releaseRoot 'distribution'
    Checked $ps @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $launcher 'Build-RuntimePackages.ps1'),'-Fable2Runtime',$runtime2,'-Fable3Runtime',$runtime3,'-Fable2Project',$f2,'-Fable3Project',$f3,'-CrtDirectory',(Join-Path $crt.FullName 'x64\Microsoft.VC143.CRT'),'-SpecPath',$specPath,'-Destination',$packages)
    Checked $ps @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $launcher 'Build.ps1'))
    Checked $ps @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $launcher 'Test.ps1'))
    Checked $ps @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $launcher 'Test.Resolution.ps1'))
    Checked $ps @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $launcher 'Test.Fps.ps1'))
    Checked $ps @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $launcher 'Test.Update.ps1'))
    Checked $ps @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $launcher 'Build-Bundle.ps1'),'-PackageDirectory',$packages,'-DecoderDirectory',$config.decoderDirectory,'-Destination',$distribution,'-ReleaseTag',$tag,'-BuildId',$buildId)
    $build=Get-Content (Join-Path $distribution 'latest-build.json') -Raw | ConvertFrom-Json
    Checked $ps @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $launcher 'Test.Release.ps1'),'-Distribution',$distribution)
    $verify=Start-Process -FilePath $build.setup -ArgumentList '--verify' -Wait -PassThru
    if($verify.ExitCode){throw 'Installer payload verification failed.'}
    $provenance=Join-Path $distribution 'source-revisions.json';$heads | ConvertTo-Json | Set-Content $provenance -Encoding UTF8
    $manifest=Join-Path $distribution 'albion-update.json';$sums=Join-Path $distribution 'SHA256SUMS.txt'
    @($build.setup,$build.portable,$manifest,$provenance) | ForEach-Object {"$((Get-FileHash $_ -Algorithm SHA256).Hash.ToLower())  $([IO.Path]::GetFileName($_))"} | Set-Content $sums -Encoding ascii
    $notes=Join-Path $distribution 'release-notes.txt'
    @("Automated Windows x64 preview from tested builds.","","Launcher: $($heads.launcher)","Fable II: $($heads.fable2)","Fable III: $($heads.fable3)","","Includes compiled runtimes, not game content. Supply your supported game files. Albion Reborn offers this update automatically; choose Download & restart. Managed game data, saves, caches, and seed settings remain in place. Native compilation and packaging checks do not replace full-game playtesting.") | Set-Content $notes -Encoding utf8
    if($ValidateOnly){Write-Output "Validated build (not published): $distribution";return}
    Checked 'gh' @('release','create',$tag,$build.setup,$build.portable,$manifest,$sums,$provenance,'--repo','DanielCoffey1/Albion-Reborn','--target',$heads.launcher,'--title',('Albion Reborn '+$buildId),'--notes-file',$notes,'--prerelease','--draft')
    Checked 'gh' @('release','edit',$tag,'--repo','DanielCoffey1/Albion-Reborn','--draft=false')
    Write-AlbionJson @{signature=$signature;tag=$tag;heads=$heads;publishedUtc=[datetime]::UtcNow.ToString('o')} $statePath
    Write-Output "Published $tag"
} finally {$lock.Dispose()}
