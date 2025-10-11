Describe "envs safeguards" {
    BeforeAll {
        . "$PSScriptRoot\envpwsh.ps1"
    }

    BeforeEach {
        $script:VarName = "ENVPSH_TEST_VAR_{0}" -f ([System.Guid]::NewGuid().ToString("N").Substring(0, 8))
        $script:OriginalPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
    }

    AfterEach {
        if ($script:VarName) {
            [Environment]::SetEnvironmentVariable($script:VarName, $null, 'Process')
        }
        [Environment]::SetEnvironmentVariable('Path', $script:OriginalPath, 'Process')
    }

    It "Appends existing values when using -Set" {
        [Environment]::SetEnvironmentVariable($script:VarName, 'foo', 'Process')
        [Environment]::SetEnvironmentVariable('Path', $script:OriginalPath, 'Process')

        $null = envs $script:VarName 'Process' 'bar' -Set

        $value = [Environment]::GetEnvironmentVariable($script:VarName, 'Process')
        $value | Should -Be 'foo;bar'

        $path = [Environment]::GetEnvironmentVariable('Path', 'Process')
        $pathParts = $path -split ';'
        $pathParts | Should -Contain "%$($script:VarName)%"
    }

    It "Throws when -Set value already present" {
        [Environment]::SetEnvironmentVariable($script:VarName, 'foo', 'Process')

        { envs $script:VarName 'Process' 'foo' -Set } | Should -Throw -ErrorId 'EnvVariableDuplicateValue'
    }

    It "Throws when PATH already contains literal value" {
        $duplicateValue = 'C:\\EnvPwsh\PathDup'
        [Environment]::SetEnvironmentVariable('Path', $duplicateValue, 'Process')

        { envs $script:VarName 'Process' $duplicateValue -Set } | Should -Throw -ErrorId 'EnvPathDuplicateValue'
    }

    It "Throws when PATH contains equivalent expanded value" {
        $token = '%TEMP%'
        $expanded = [Environment]::ExpandEnvironmentVariables($token)
        [Environment]::SetEnvironmentVariable('Path', $token, 'Process')

        { envs $script:VarName 'Process' $expanded -Set } | Should -Throw -ErrorId 'EnvPathDuplicateValue'
    }

    It "Throws when -Append receives duplicate value" {
        [Environment]::SetEnvironmentVariable($script:VarName, 'foo;bar', 'Process')

        { envs $script:VarName 'Process' 'bar' -Append } | Should -Throw -ErrorId 'EnvVariableDuplicateValue'
    }
}
